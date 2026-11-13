# Pruebas unitarias de policy/container.rego (Ítem 3.4) — se ejecutan con `conftest verify`.
# Las entradas reproducen la estructura que entrega Conftest:
#   --parser dockerfile → [{Cmd, Value, Stage}, ...]   ·   compose YAML → {services: {...}}
package main

import rego.v1

# ---------- utilidades para construir Dockerfiles de prueba ----------
from(stage) := {"Cmd": "from", "Value": ["node:22-alpine"], "Stage": stage}

user(value, stage) := {"Cmd": "user", "Value": [value], "Stage": stage}

run(stage) := {"Cmd": "run", "Value": ["npm ci"], "Stage": stage}

# =====================================================================
# Dockerfile — casos permitidos
# =====================================================================
test_dockerfile_user_node_allowed if {
	count(deny) == 0 with input as [from(0), run(0), user("node", 0)]
}

test_dockerfile_numeric_non_root_allowed if {
	count(deny) == 0 with input as [from(0), user("101", 0)]
}

test_dockerfile_uid_gid_non_root_allowed if {
	count(deny) == 0 with input as [from(0), user("1000:1000", 0)]
}

# Patrón del frontend real: root temporal para `apk upgrade` y vuelta a 101.
test_dockerfile_root_then_non_root_allowed if {
	count(deny) == 0 with input as [from(0), user("root", 0), run(0), user("101", 0)]
}

# Multi-stage: la etapa de build puede ser root si la final no lo es.
test_dockerfile_multistage_root_build_non_root_final_allowed if {
	count(deny) == 0 with input as [from(0), user("root", 0), run(0), from(1), user("node", 1)]
}

# =====================================================================
# Dockerfile — casos rechazados
# =====================================================================
test_dockerfile_without_user_denied if {
	some msg in deny with input as [from(0), run(0)]
	contains(msg, "no declara ninguna instrucción USER")
	contains(msg, "THR-05/CTL-05")
}

test_dockerfile_user_root_denied if {
	some msg in deny with input as [from(0), user("root", 0)]
	contains(msg, "'root'")
}

test_dockerfile_user_root_uppercase_denied if {
	count(deny) > 0 with input as [from(0), user("ROOT", 0)]
}

test_dockerfile_user_zero_denied if {
	count(deny) > 0 with input as [from(0), user("0", 0)]
}

test_dockerfile_user_zero_zero_denied if {
	count(deny) > 0 with input as [from(0), user("0:0", 0)]
}

test_dockerfile_user_root_group_denied if {
	count(deny) > 0 with input as [from(0), user("root:root", 0)]
}

test_dockerfile_user_empty_denied if {
	some msg in deny with input as [from(0), user("", 0)]
	contains(msg, "vacía")
}

test_dockerfile_user_without_value_denied if {
	some msg in deny with input as [from(0), {"Cmd": "user", "Value": [], "Stage": 0}]
	contains(msg, "vacía")
}

# El último USER manda: volver a root al final se rechaza.
test_dockerfile_non_root_then_root_denied if {
	count(deny) > 0 with input as [from(0), user("node", 0), user("root", 0)]
}

# Multi-stage: un USER no root en la etapa de build NO protege la etapa final.
test_dockerfile_user_only_in_build_stage_denied if {
	some msg in deny with input as [from(0), user("node", 0), from(1), run(1)]
	contains(msg, "no declara ninguna instrucción USER")
}

# =====================================================================
# docker-compose — casos permitidos
# =====================================================================
test_compose_secure_allowed if {
	count(deny) == 0 with input as {"services": {
		"backend": {"image": "x", "read_only": true, "cap_drop": ["ALL"]},
		"frontend": {"image": "y", "privileged": false},
	}}
}

test_compose_non_root_user_allowed if {
	count(deny) == 0 with input as {"services": {"backend": {"user": "1000:1000"}}}
}

# =====================================================================
# docker-compose — casos rechazados
# =====================================================================
test_compose_privileged_denied if {
	some msg in deny with input as {"services": {"backend": {"privileged": true}}}
	contains(msg, "'backend'")
	contains(msg, "privileged: true")
	contains(msg, "THR-05/CTL-05")
}

test_compose_user_root_denied if {
	some msg in deny with input as {"services": {"db": {"user": "root"}}}
	contains(msg, "'db'")
}

test_compose_user_zero_string_denied if {
	count(deny) > 0 with input as {"services": {"db": {"user": "0"}}}
}

# YAML `user: 0` sin comillas llega como número.
test_compose_user_zero_number_denied if {
	count(deny) > 0 with input as {"services": {"db": {"user": 0}}}
}

test_compose_user_zero_zero_denied if {
	count(deny) > 0 with input as {"services": {"db": {"user": "0:0"}}}
}

test_compose_reports_every_violation if {
	count(deny) == 2 with input as {"services": {
		"a": {"privileged": true},
		"b": {"user": "root"},
	}}
}

# =====================================================================
# Entradas no reconocidas: advertencia (no pasan en silencio)
# =====================================================================
test_unknown_input_warns if {
	count(warn) == 1 with input as {"kind": "ConfigMap"}
}

test_known_inputs_do_not_warn if {
	count(warn) == 0 with input as [from(0), user("node", 0)]
	count(warn) == 0 with input as {"services": {"a": {}}}
}
