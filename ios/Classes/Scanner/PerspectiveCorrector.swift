import UIKit
import CoreImage

/// Corrige la perspective d'un document pour le rendre plat
@available(iOS 13.0, *)
class PerspectiveCorrector {

    /// Applique une correction de perspective à une image
    /// - Parameters:
    ///   - image: L'image source
    ///   - topLeft: Coin supérieur gauche (en coordonnées de l'image)
    ///   - topRight: Coin supérieur droit
    ///   - bottomLeft: Coin inférieur gauche
    ///   - bottomRight: Coin inférieur droit
    /// - Returns: L'image corrigée ou nil en cas d'erreur
    func correctPerspective(
        image: UIImage,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) -> UIImage? {
        guard let ciImage = CIImage(image: image) else {
            return nil
        }

        // Convertir les coordonnées UIKit (origine en haut à gauche)
        // vers les coordonnées CoreImage (origine en bas à gauche)
        let imageHeight = ciImage.extent.height

        let ciTopLeft = CGPoint(x: topLeft.x, y: imageHeight - topLeft.y)
        let ciTopRight = CGPoint(x: topRight.x, y: imageHeight - topRight.y)
        let ciBottomLeft = CGPoint(x: bottomLeft.x, y: imageHeight - bottomLeft.y)
        let ciBottomRight = CGPoint(x: bottomRight.x, y: imageHeight - bottomRight.y)

        // Appliquer le filtre de correction de perspective
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: ciTopLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: ciTopRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: ciBottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: ciBottomRight), forKey: "inputBottomRight")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        // Convertir CIImage en UIImage
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Applique une correction de perspective en utilisant des points normalisés (0-1)
    func correctPerspective(
        image: UIImage,
        normalizedTopLeft: CGPoint,
        normalizedTopRight: CGPoint,
        normalizedBottomLeft: CGPoint,
        normalizedBottomRight: CGPoint
    ) -> UIImage? {
        let imageSize = image.size

        let topLeft = CGPoint(
            x: normalizedTopLeft.x * imageSize.width,
            y: normalizedTopLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: normalizedTopRight.x * imageSize.width,
            y: normalizedTopRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: normalizedBottomLeft.x * imageSize.width,
            y: normalizedBottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: normalizedBottomRight.x * imageSize.width,
            y: normalizedBottomRight.y * imageSize.height
        )

        return correctPerspective(
            image: image,
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight
        )
    }

    /// Convertit les points Vision (origine en bas à gauche, normalisés)
    /// vers les coordonnées UIKit pour une image donnée
    func convertVisionPoints(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint,
        imageSize: CGSize
    ) -> (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        // Vision utilise des coordonnées normalisées avec origine en bas à gauche
        // UIKit utilise origine en haut à gauche
        let convertPoint: (CGPoint) -> CGPoint = { point in
            CGPoint(
                x: point.x * imageSize.width,
                y: (1 - point.y) * imageSize.height
            )
        }

        return (
            topLeft: convertPoint(topLeft),
            topRight: convertPoint(topRight),
            bottomLeft: convertPoint(bottomLeft),
            bottomRight: convertPoint(bottomRight)
        )
    }
}
