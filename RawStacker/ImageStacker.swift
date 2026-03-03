import CoreImage
import Vision

class ImageStacker {
    func stackImages(urls: [URL], completion: @escaping (CIImage?) -> Void) {
        guard !urls.isEmpty else {
            completion(nil)
            return
        }
        
        // 1. Start with the first image as the base
        var accumulator: CIImage? = CIImage(contentsOf: urls[0])
        
        // 2. Loop through the remaining images (starting at index 1)
        for i in 1..<urls.count {
            autoreleasepool {
                guard let nextImage = CIImage(contentsOf: urls[i]),
                      let currentBase = accumulator else { return }
                
                // Align the new frame to our running stack
                let aligned = align(reference: currentBase, target: nextImage)
                
                // CALCULATE WEIGHT: To get a true average:
                // Image 2 needs 1/2 opacity (0.5)
                // Image 3 needs 1/3 opacity (0.33)
                // Image 4 needs 1/4 opacity (0.25)
                let alpha = 1.0 / Double(i + 1)
                
                // Blend 'aligned' over 'currentBase' using the alpha weight
                let filter = CIFilter(name: "CISourceOverCompositing")!
                
                // Apply the alpha to the NEW image before placing it on top
                let weightedImage = aligned.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ])
                
                filter.setValue(weightedImage, forKey: kCIInputImageKey)
                filter.setValue(currentBase, forKey: kCIInputBackgroundImageKey)
                
                accumulator = filter.outputImage
            }
        }
        
        completion(accumulator)
    }
    
    private func align(reference: CIImage, target: CIImage) -> CIImage {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: target)
        let handler = VNImageRequestHandler(ciImage: reference, options: [:])
        
        do {
            try handler.perform([request])
            if let observation = request.results?.first as? VNImageTranslationAlignmentObservation {
                // Shift the target image to perfectly overlap the reference
                return target.transformed(by: observation.alignmentTransform)
            }
        } catch {
            print("Alignment error: \(error)")
        }
        return target
    }
}
