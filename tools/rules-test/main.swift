import Foundation
let samples = [
    "eh hola  eh  como estas ,  quiero  pedir  una  tapa de 5 litros .",
    "dale mi hermano voy a aplicar esa pues ya espero que esta vez funcione estaba viendo no encuentro o sea estoy encontrando tapas pero por ejemplo de 5 litros donde el largo tienen 29.5 altura 13.5 y ancho 18.5 esos tapas me servirían y segundo recordemos que mi caja es de 40 centímetros de alto por 60 centímetros de ancho",
    "The chase is working so good. Whisperflow funciona igual. Creo que tiene un filtro igual como de mejora del texto con inteligencia artificial."
]
for s in samples {
    print("IN :", s)
    print("OUT:", RulesCleaner.clean(s))
    print("---")
}
