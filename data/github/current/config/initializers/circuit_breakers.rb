# frozen_string_literal: true

require "github/circuit_breaker/patch/default_properties"

# Patch the circuit breaker properties to provide GitHub-specific defaults.
Resilient::CircuitBreaker::Properties.prepend(GitHub::CircuitBreaker::Patch::DefaultProperties)
