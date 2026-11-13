# =============================================================================
# Ítem 3.4 — Políticas de configuración de contenedores (THR-05 / CTL-05)
# Responsable: Brandon Corrales · Revisor: Billy Ugalde
#
# Un único archivo con las dos políticas exigidas, aplicadas a cada tipo de archivo:
#
#   Política 1 — No ejecutar contenedores en modo privilegiado.
#     · docker-compose (archivo de DESPLIEGUE): ningún servicio con `privileged: true`.
#   Política 2 — Usuario no root explícito.
#     · Dockerfile (archivo de CONSTRUCCIÓN): la etapa final debe tener una instrucción
#       USER y la última no puede ser vacía, `root` ni UID/GID 0.
#     · docker-compose (archivo de DESPLIEGUE): `user:` no puede sobrescribirlo con root/0.
#
# Tipo de entrada (Conftest):
#   · `--parser dockerfile` → arreglo de instrucciones {Cmd, Value, Stage, ...}
#   · YAML de compose       → objeto con la clave `services`
#
# Uso: conftest test --policy policy --parser dockerfile backend/Dockerfile
#      conftest test --policy policy --parser yaml docker-compose.yml
# =============================================================================
package main

import rego.v1

# -----------------------------------------------------------------------------
# Detección del tipo de entrada
# -----------------------------------------------------------------------------
is_dockerfile if {
	is_array(input)
	some instr in input
	instr.Cmd == "from"
}

is_compose if {
	is_object(input)
	is_object(input.services)
}

# Sin esta advertencia, un archivo que no es Dockerfile ni compose "pasaría"
# en silencio sin que se le aplique ninguna política.
warn contains msg if {
	not is_dockerfile
	not is_compose
	msg := "[THR-05/CTL-05] Entrada no reconocida como Dockerfile ni docker-compose: no se aplicaron las políticas de contenedor. Use --parser dockerfile para Dockerfiles."
}

# -----------------------------------------------------------------------------
# Utilidad: ¿el valor de usuario (`usuario[:grupo]`) corresponde a root?
# -----------------------------------------------------------------------------
root_identity(value) if {
	user_part := lower(trim_space(split(sprintf("%v", [value]), ":")[0]))
	user_part in {"root", "0"}
}

# Valor vacío o compuesto solo de espacios.
blank(value) if trim_space(sprintf("%v", [value])) == ""

# -----------------------------------------------------------------------------
# Dockerfile — Política 2: USER no root explícito en la etapa final
# -----------------------------------------------------------------------------
final_stage := max({instr.Stage | some instr in input; instr.Cmd == "from"}) if is_dockerfile

final_users := [instr |
	some instr in input
	instr.Cmd == "user"
	instr.Stage == final_stage
]

last_final_user := final_users[count(final_users) - 1].Value[0] if count(final_users) > 0

deny contains msg if {
	is_dockerfile
	count(final_users) == 0
	msg := "[THR-05/CTL-05] Dockerfile: la etapa final no declara ninguna instrucción USER, por lo que el contenedor se ejecutaría como root. Corrección: agregue 'USER <usuario no root>' (por ejemplo 'USER node' o 'USER 101') en la etapa final, después de los pasos que requieren root."
}

deny contains msg if {
	is_dockerfile
	count(final_users) > 0
	not last_final_user
	msg := "[THR-05/CTL-05] Dockerfile: la última instrucción USER de la etapa final está vacía. Corrección: indique un usuario no root explícito, por ejemplo 'USER node'."
}

deny contains msg if {
	is_dockerfile
	blank(last_final_user)
	msg := "[THR-05/CTL-05] Dockerfile: la última instrucción USER de la etapa final está vacía. Corrección: indique un usuario no root explícito, por ejemplo 'USER node'."
}

deny contains msg if {
	is_dockerfile
	root_identity(last_final_user)
	msg := sprintf("[THR-05/CTL-05] Dockerfile: la última instrucción USER de la etapa final es '%v', que corresponde a root (UID 0). Corrección: termine la etapa final con un usuario sin privilegios, por ejemplo 'USER node' (UID 1000) o 'USER 101'; si necesita root para instalar paquetes, vuelva al usuario no root después.", [last_final_user])
}

# -----------------------------------------------------------------------------
# docker-compose — Política 1: sin modo privilegiado
# -----------------------------------------------------------------------------
deny contains msg if {
	is_compose
	some name, svc in input.services
	svc.privileged == true
	msg := sprintf("[THR-05/CTL-05] docker-compose: el servicio '%s' usa 'privileged: true', que da acceso a todos los dispositivos y capacidades del host (permite escapar del contenedor). Corrección: elimine 'privileged' y, si hace falta, otorgue solo la capacidad mínima con 'cap_add'.", [name])
}

# -----------------------------------------------------------------------------
# docker-compose — Política 2: no sobrescribir el usuario con root
# -----------------------------------------------------------------------------
deny contains msg if {
	is_compose
	some name, svc in input.services
	root_identity(svc.user)
	msg := sprintf("[THR-05/CTL-05] docker-compose: el servicio '%s' fuerza 'user: %v' (root), anulando el USER no root de la imagen. Corrección: elimine 'user:' para usar el de la imagen o indique un UID no root, por ejemplo 'user: \"1000:1000\"'.", [name, svc.user])
}
