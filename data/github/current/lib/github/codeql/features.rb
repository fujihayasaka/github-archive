# typed: true
# frozen_string_literal: true

require "github/codeql/action"

module GitHub
  module CodeQL
    class Features
      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_0_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_0, :code_scanning_default_codeql_version_2_24_0_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_1_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_1, :code_scanning_default_codeql_version_2_24_1_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_2_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_2, :code_scanning_default_codeql_version_2_24_2_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_3_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_3, :code_scanning_default_codeql_version_2_24_3_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_4_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_4, :code_scanning_default_codeql_version_2_24_4_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_5_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_5, :code_scanning_default_codeql_version_2_24_5_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_6_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_6, :code_scanning_default_codeql_version_2_24_6_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_7_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_7, :code_scanning_default_codeql_version_2_24_7_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_8_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_8, :code_scanning_default_codeql_version_2_24_8_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_24_9_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_24_9, :code_scanning_default_codeql_version_2_24_9_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_25_0_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_25_0, :code_scanning_default_codeql_version_2_25_0_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_25_1_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_25_1, :code_scanning_default_codeql_version_2_25_1_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_25_2_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_25_2, :code_scanning_default_codeql_version_2_25_2_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_25_3_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_25_3, :code_scanning_default_codeql_version_2_25_3_disabled)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.default_codeql_version_2_25_4_enabled?(repository)
        repository.check_enabled_and_disabled_flags?(:code_scanning_default_codeql_version_2_25_4, :code_scanning_default_codeql_version_2_25_4_disabled)
      end
    end
  end
end
