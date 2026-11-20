import Foundation
import FoundationModels

print("== availability ==")
print(SystemLanguageModel.default.availability)

let raw = """
dale mi hermano voy a aplicar esa pues ya espero que esta vez funcione estaba viendo no encuentro o sea estoy encontrando tapas pero por ejemplo de 5 litros donde el largo tienen 29.5 altura 13.5 y ancho 18.5 esos tapas me servirían y segundo recordemos que mi caja es de 40 centímetros de alto por 60 centímetros de ancho
"""

print("\n== texto crudo ==")
print(raw)

let session = LanguageModelSession(instructions: """
Eres un posprocesador de dictado por voz. Devuelves el mismo contenido limpio: \
corrige puntuación y mayúsculas, quita muletillas (eh, um, este, o sea, pues cuando no aportan), \
no traduzcas, no resumas, no agregues información, mantén el idioma original. \
Devuelve solo el texto final, sin comillas ni explicaciones.
""")

let start = Date()
do {
    let response = try await session.respond(to: raw, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 900))
    print("\n== limpiado (\(String(format: "%.2f", Date().timeIntervalSince(start)))s) ==")
    print(response.content)
} catch {
    print("ERROR: \(error)")
}
