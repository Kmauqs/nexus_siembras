# Guía del tester — NEXUS Siembras
**C2-9b · 1 página · v0.2.8** · Android y Windows

Bienvenido. Estás probando la **versión abierta** de NEXUS Siembras (control agropecuario offline-first). No hace falta conocimiento técnico: usa la app como en el campo y cuéntanos qué falló o qué faltó.

---

## Antes de empezar

1. Instala el build que te enviaron (APK Android o instalador Windows).
2. Crea una cuenta con **tu email real** (o la de prueba que te indiquen) e inicia sesión.
3. Anota la **versión** que ves al enviar comentarios (la app la adjunta sola) y en qué plataforma estás (Android / Windows).
4. Si te piden probar **colaboradores**, necesitas **dos cuentas** (o un segundo dispositivo/emulador).

---

## Cómo reportar (canal oficial)

| Qué | Dónde |
|-----|--------|
| Comentario, bug o idea | Menú ☰ → **Enviar comentarios** |
| Sin internet | Igual: se guarda en el teléfono/PC y sube solo cuando haya red y sesión |
| Error de sync u otro fallo técnico | Menú → **Reportes** → *Logs de diagnóstico* → **Compartir** (adjúntalo al comentario o envíalo aparte) |
| Historial de lo que ya enviaste | En la misma pantalla de comentarios (estados *pendiente* / *enviado*) |

**Tips:** estrellas + chips + un comentario concreto («en Compra no pude adjuntar PDF», no solo «no funciona»). Si es un error, marca el chip *Encontré un error* o escribe el tipo `bug` en el texto.

---

## Recorridos mínimos (qué probar)

Haz al menos estos caminos. Marca ✓ / ✗ / n/a y reporta lo que falle.

| # | Recorrido | Qué mirar |
|---|-----------|-----------|
| 1 | **Onboarding + Asistente** | Menú → Asistente: predio → lote → condiciones → suelo → proveedor → variedad → compra → inventario → cultivo → mapa. ¿Se puede avanzar/volver sin perder datos? |
| 2 | **Ciclo cultivo** | Crear cultivo → registrar tarea (desde cronograma o detalle) → cosecha. ¿Fechas y HH cuadran? |
| 3 | **Compra con comprobante** | Compra del año con PDF o foto adjunta; abrir el adjunto después. |
| 4 | **Mapa y patología** | Mapa con GPS; reportar patología con foto (opcional: compartir a comunidad). |
| 5 | **Exportes / Reportes** | Dashboard o Reportes: generar PDF/CSV y abrir/compartir. |
| 6 | **Multi-usuario** *(si aplica)* | Dueño invita colaborador (`trabajador` o `consultor`); el invitado acepta, sincroniza y ve predio/cultivos según el rol. |
| 7 | **Sin red** | Modo avión: crear un cultivo o tarea; al volver la red, **Sincronizar** y comprobar que subió. |
| 8 | **Backup** *(opcional)* | Configuración → exportar JSON; en otro momento importar (cuenta de prueba). |
| 9 | **Borrar cuenta** *(solo cuenta desechable)* | Configuración / cuenta → eliminar con confirmación de email. **No** uses tu cuenta principal. |

---

## Qué no hace falta

- No necesitas conocer Supabase, Git ni SQL.
- No reinicies a medias un borrado de cuenta en una cuenta que quieras conservar.
- Si algo “no sincroniza”, primero pulsa **Sincronizar**, luego comparte los logs de Reportes.

Gracias: tu feedback llega a la bandeja del equipo y nos permite priorizar arreglos antes de la release estable.
