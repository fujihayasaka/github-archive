# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  class Utils
    sig { params(vm_generation: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.vm_generation_to_pb(vm_generation)
      {
        "Gen1" => :Gen1,
        "Gen2" => :Gen2,
      }[vm_generation]
    end

    sig { params(os_state: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.os_state_to_pb(os_state)
      {
        "Generalized" => :Generalized,
        "Specialized" => :Specialized,
      }[os_state]
    end

    sig { params(os_type: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.os_type_to_pb(os_type)
      {
        "Linux" => :Linux,
        "Windows" => :Windows,
        "MacOS" => :MacOS
      }[os_type]
    end

    sig { params(architecture: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.architecture_to_pb(architecture)
      {
        "X64" => :X64,
        "Arm64" => :Arm64,
      }[architecture]
    end
  end
end
