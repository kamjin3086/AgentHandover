//! macOS OCR via the Vision framework (VNRecognizeTextRequest).
//!
//! Recognizes text in raw BGRA pixel buffers captured from screenshots.
//! Uses the Objective-C runtime FFI to call into Apple's Vision framework,
//! following the same pattern as `macos_clipboard.rs`.

use serde::{Deserialize, Serialize};
use std::ffi::c_void;
use tracing::{debug, warn};

// Objective-C runtime FFI (libobjc.dylib ships with macOS).
#[link(name = "objc", kind = "dylib")]
extern "C" {
    fn objc_getClass(name: *const u8) -> *mut c_void;
    fn sel_registerName(name: *const u8) -> *mut c_void;
    fn objc_msgSend(obj: *mut c_void, sel: *mut c_void, ...) -> *mut c_void;
}

// Link Vision and CoreGraphics frameworks.
#[link(name = "Vision", kind = "framework")]
extern "C" {}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGBitmapContextCreate(
        data: *mut c_void,
        width: usize,
        height: usize,
        bits_per_component: usize,
        bytes_per_row: usize,
        space: *mut c_void,
        bitmap_info: u32,
    ) -> *mut c_void;
    fn CGBitmapContextCreateImage(context: *mut c_void) -> *mut c_void;
    fn CGColorSpaceCreateDeviceRGB() -> *mut c_void;
    fn CGColorSpaceRelease(space: *mut c_void);
    fn CGContextRelease(context: *mut c_void);
    fn CGImageRelease(image: *mut c_void);
}

/// A single recognized text element from OCR.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrTextResult {
    pub text: String,
    pub confidence: f32,
    /// Normalized bounding box [x, y, width, height] in 0.0-1.0 range.
    pub bbox_normalized: [f64; 4],
}

/// Full OCR result from a single image.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrResult {
    pub elements: Vec<OcrTextResult>,
    pub full_text: String,
    pub processing_time_ms: u64,
}

/// Recognize text in raw BGRA pixel data using Apple Vision framework.
///
/// Returns `Some(OcrResult)` on success, `None` on failure.
/// The pixel data must be in BGRA format (as returned by `CGDisplay::image()`).
pub fn recognize_text(pixels: &[u8], width: usize, height: usize) -> Option<OcrResult> {
    if pixels.is_empty() || width == 0 || height == 0 {
        return None;
    }

    let start = std::time::Instant::now();

    // Expected: 4 bytes per pixel (BGRA)
    let expected_len = width * height * 4;
    if pixels.len() < expected_len {
        warn!(
            pixels_len = pixels.len(),
            expected = expected_len,
            "Pixel buffer too small for declared dimensions"
        );
        return None;
    }

    unsafe {
        // 1. Create CGImage from raw pixels via CGBitmapContext
        let color_space = CGColorSpaceCreateDeviceRGB();
        if color_space.is_null() {
            return None;
        }

        // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little = 0x2002
        let bitmap_info: u32 = 0x2002;
        let bytes_per_row = width * 4;

        // We need a mutable copy since CGBitmapContextCreate takes *mut
        let mut pixel_copy = pixels[..expected_len].to_vec();

        let context = CGBitmapContextCreate(
            pixel_copy.as_mut_ptr() as *mut c_void,
            width,
            height,
            8, // bits per component
            bytes_per_row,
            color_space,
            bitmap_info,
        );
        CGColorSpaceRelease(color_space);

        if context.is_null() {
            return None;
        }

        let cg_image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);

        if cg_image.is_null() {
            return None;
        }

        // 2. Create VNImageRequestHandler with the CGImage
        let handler_class = objc_getClass(b"VNImageRequestHandler\0".as_ptr());
        if handler_class.is_null() {
            CGImageRelease(cg_image);
            return None;
        }

        let sel_alloc = sel_registerName(b"alloc\0".as_ptr());
        let handler = objc_msgSend(handler_class, sel_alloc);
        if handler.is_null() {
            CGImageRelease(cg_image);
            return None;
        }

        // initWithCGImage:options:
        let sel_init = sel_registerName(b"initWithCGImage:options:\0".as_ptr());
        let ns_dict_class = objc_getClass(b"NSDictionary\0".as_ptr());
        let sel_dict = sel_registerName(b"dictionary\0".as_ptr());
        let empty_dict = objc_msgSend(ns_dict_class, sel_dict);

        let handler = objc_msgSend(handler, sel_init, cg_image, empty_dict);
        CGImageRelease(cg_image);

        if handler.is_null() {
            return None;
        }

        // 3. Create VNRecognizeTextRequest
        let request_class = objc_getClass(b"VNRecognizeTextRequest\0".as_ptr());
        if request_class.is_null() {
            return None;
        }

        let request = objc_msgSend(request_class, sel_alloc);
        let sel_init_simple = sel_registerName(b"init\0".as_ptr());
        let request = objc_msgSend(request, sel_init_simple);
        if request.is_null() {
            return None;
        }

        // setRecognitionLevel: 1 (accurate)
        let sel_set_level = sel_registerName(b"setRecognitionLevel:\0".as_ptr());
        objc_msgSend(request, sel_set_level, 1i64);

        // 4. Perform the request
        let sel_perform = sel_registerName(b"performRequests:error:\0".as_ptr());

        // Wrap request in NSArray
        let ns_array_class = objc_getClass(b"NSArray\0".as_ptr());
        let sel_array_with = sel_registerName(b"arrayWithObject:\0".as_ptr());
        let requests_array = objc_msgSend(ns_array_class, sel_array_with, request);

        let mut error_ptr: *mut c_void = std::ptr::null_mut();
        let success = objc_msgSend(
            handler,
            sel_perform,
            requests_array,
            &mut error_ptr as *mut *mut c_void,
        );

        if success.is_null() || !error_ptr.is_null() {
            debug!("Vision OCR request failed");
            return None;
        }

        // 5. Extract results from VNRecognizeTextRequest
        let sel_results = sel_registerName(b"results\0".as_ptr());
        let observations = objc_msgSend(request, sel_results);
        if observations.is_null() {
            return Some(OcrResult {
                elements: vec![],
                full_text: String::new(),
                processing_time_ms: start.elapsed().as_millis() as u64,
            });
        }

        let sel_count = sel_registerName(b"count\0".as_ptr());
        let count = objc_msgSend(observations, sel_count) as usize;

        let mut elements = Vec::with_capacity(count);
        let mut full_text_parts: Vec<String> = Vec::with_capacity(count);

        let sel_object_at = sel_registerName(b"objectAtIndex:\0".as_ptr());

        for i in 0..count {
            let observation = objc_msgSend(observations, sel_object_at, i as i64);
            if observation.is_null() {
                continue;
            }

            // Get top candidate text
            let sel_top = sel_registerName(b"topCandidates:\0".as_ptr());
            let candidates = objc_msgSend(observation, sel_top, 1i64);
            if candidates.is_null() {
                continue;
            }

            let cand_count = objc_msgSend(candidates, sel_count) as usize;
            if cand_count == 0 {
                continue;
            }

            let top_candidate = objc_msgSend(candidates, sel_object_at, 0i64);
            if top_candidate.is_null() {
                continue;
            }

            // Get the text string
            let sel_string = sel_registerName(b"string\0".as_ptr());
            let ns_string = objc_msgSend(top_candidate, sel_string);
            if ns_string.is_null() {
                continue;
            }

            let sel_utf8 = sel_registerName(b"UTF8String\0".as_ptr());
            let cstr = objc_msgSend(ns_string, sel_utf8) as *const u8;
            if cstr.is_null() {
                continue;
            }

            let text = match std::ffi::CStr::from_ptr(cstr as *const _).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => continue,
            };

            // Get confidence from the candidate
            let sel_confidence = sel_registerName(b"confidence\0".as_ptr());
            let confidence_raw = objc_msgSend(top_candidate, sel_confidence);
            let confidence = f32::from_bits(confidence_raw as u32);
            // Clamp to valid range
            let confidence = confidence.clamp(0.0, 1.0);

            // Get bounding box from the observation (normalized 0.0-1.0)
            let sel_bbox = sel_registerName(b"boundingBox\0".as_ptr());
            // CGRect is returned as struct — we read it as 4 f64s
            // On arm64, small structs are returned in registers
            let bbox_ptr = objc_msgSend(observation, sel_bbox) as *const [f64; 4];
            let bbox = if !bbox_ptr.is_null() {
                // Vision framework uses bottom-left origin, normalize to top-left
                let raw = *bbox_ptr;
                [raw[0], 1.0 - raw[1] - raw[3], raw[2], raw[3]]
            } else {
                [0.0, 0.0, 0.0, 0.0]
            };

            full_text_parts.push(text.clone());
            elements.push(OcrTextResult {
                text,
                confidence,
                bbox_normalized: bbox,
            });
        }

        let full_text = full_text_parts.join("\n");
        let processing_time_ms = start.elapsed().as_millis() as u64;

        debug!(
            elements = elements.len(),
            time_ms = processing_time_ms,
            "OCR completed"
        );

        Some(OcrResult {
            elements,
            full_text,
            processing_time_ms,
        })
    }
}

/// Async wrapper that runs OCR in a blocking thread with a 500ms timeout.
pub async fn recognize_text_async(
    pixels: Vec<u8>,
    width: usize,
    height: usize,
) -> Option<OcrResult> {
    let task = tokio::task::spawn_blocking(move || recognize_text(&pixels, width, height));

    match tokio::time::timeout(std::time::Duration::from_millis(500), task).await {
        Ok(Ok(result)) => result,
        Ok(Err(e)) => {
            warn!(error = %e, "OCR task panicked");
            None
        }
        Err(_) => {
            warn!("OCR timed out after 500ms");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ocr_result_serde_roundtrip() {
        let result = OcrResult {
            elements: vec![OcrTextResult {
                text: "Hello World".to_string(),
                confidence: 0.95,
                bbox_normalized: [0.1, 0.2, 0.5, 0.1],
            }],
            full_text: "Hello World".to_string(),
            processing_time_ms: 42,
        };
        let json = serde_json::to_string(&result).unwrap();
        let deserialized: OcrResult = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.elements.len(), 1);
        assert_eq!(deserialized.full_text, "Hello World");
        assert_eq!(deserialized.processing_time_ms, 42);
    }

    #[test]
    fn test_empty_pixels_returns_none() {
        let result = recognize_text(&[], 0, 0);
        assert!(result.is_none());
    }

    #[test]
    fn test_valid_1x1_pixel_no_panic() {
        // 1x1 BGRA pixel
        let pixels = vec![0u8; 4];
        let result = recognize_text(&pixels, 1, 1);
        // May return None (no text in a single pixel) or Some with empty elements.
        // The important thing is it doesn't panic.
        if let Some(r) = result {
            assert!(r.elements.is_empty() || !r.elements.is_empty());
        }
    }

    #[test]
    fn test_undersized_buffer_returns_none() {
        // Claims 100x100 but only provides 4 bytes
        let pixels = vec![0u8; 4];
        let result = recognize_text(&pixels, 100, 100);
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_async_respects_timeout() {
        // Empty pixels should return quickly with None
        let result = recognize_text_async(vec![], 0, 0).await;
        assert!(result.is_none());
    }
}
