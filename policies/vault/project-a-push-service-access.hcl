path "secrets/data/{{env}}/{{project}}-{{service}}/*" {
  capabilities = ["read", "list"]
}

path "secrets/metadata/{{env}}/{{project}}-{{service}}/*" {
  capabilities = ["read", "list"]
}

path "configurations/data/{{env}}/{{project}}-{{service}}/*" {
  capabilities = ["read", "list"]
}

path "configurations/metadata/{{env}}/{{project}}-{{service}}/*" {
  capabilities = ["read", "list"]
}
