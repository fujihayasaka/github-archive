variable "environments" {
  description = "A list of objects describing the required attributes for creating request orchestrator infra in different environments"
  type = map(object({
      key_keeper_date              = string   # The date when the keys were generated
  }))
  default = {
    lab = {
      key_keeper_date              = "2025-03-13",
    },
  }
}
