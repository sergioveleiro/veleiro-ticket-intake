# Paquete administrado (managed package)

Cómo se construye y publica el ticket intake como paquete administrado de 2ª generación.

## Las piezas

| Pieza | Dónde vive |
|---|---|
| **Namespace** `veleiro` | Developer Edition del namespace (la misma del kit; el prefijo se comparte) |
| **Dev Hub** | Veleiro Main (`veleiro-ai.my.salesforce.com`) |
| **Paquete** | `Veleiro Ticket Intake` · `0HoPe00000003U9KAI` · Managed |

Comparte namespace con el kit, pero es **un paquete aparte**: se instala, actualiza y desinstala por su cuenta.

## La rama `packaging`

`main` es la versión sin namespace, desplegable desde el código fuente. `packaging` añade lo que exige el empaquetado:

- `sfdx-project.json` con `"namespace": "veleiro"` y la definición del paquete.
- La flexipage referencia `veleiro:veleiroTicketConfig`.

Los cambios funcionales se hacen en `main` y se traen a `packaging` antes de publicar.

## Publicar una versión

```bash
git checkout packaging && git merge main

sf package version create --package "Veleiro Ticket Intake" \
  --installation-key-bypass --code-coverage --target-dev-hub veleiro-ro --wait 45

sf package version report --package <04t...> -v veleiro-ro      # Code Coverage Met: true
sf package install --package <04t...> -o <scratch> --wait 20 --publish-wait 20 --no-prompt
sf package version promote --package <04t...> -v veleiro-ro     # IRREVERSIBLE
```

## Historial de versiones

| Versión | Id de suscriptor | Cobertura | Estado |
|---|---|---|---|
| 1.0.0.1 | `04tPe0000010op3IAA` | 90% | Beta (sin promover) · instalada y verificada junto al kit |

## Convivencia con el kit

Probado: los dos paquetes instalados en la misma org sin conflictos. El enrutamiento reconoce los campos del kit tanto si está instalado como paquete administrado (`veleiro__Veleiro_Client_Id__c`) como si está desplegado desde el código fuente (`Veleiro_Client_Id__c`).
