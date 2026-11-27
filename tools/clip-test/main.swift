import Foundation
// Reproduce el bug: un pegado "roba" el portapapeles y programa su restauración;
// si el usuario copia antes, la restauración NO debe pisar la copia nueva.
let original = "PORTAPAPELES_VIEJO_DEL_USUARIO"
Clipboard.write(original)

Clipboard.writeTemporarily("texto dictado para pegar", restoring: original, after: 0.6)
print("tras el pegado:      ", Clipboard.currentText() ?? "nil")

// el usuario pulsa "Copiar" 0.2s después
Thread.sleep(forTimeInterval: 0.2)
Clipboard.copy("MICOPIA_REAL_DEL_USUARIO")
print("tras pulsar Copiar:  ", Clipboard.currentText() ?? "nil")

// esperar a que expire el restaurador
Thread.sleep(forTimeInterval: 0.8)
let final = Clipboard.currentText() ?? "nil"
print("tras el restaurador: ", final)
print(final == "MICOPIA_REAL_DEL_USUARIO" ? "✅ CORRECTO: la copia sobrevivió" : "❌ BUG: el restaurador pisó la copia")
