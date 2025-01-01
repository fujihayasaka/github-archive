# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class FileExtensionRestrictionRule < CommitRule
      sig { void }
      def initialize
        super(rule_name: "file_extension_restriction",
              display_name: "Restrict file extensions",
              description: "Prevent commits that include files with specified file extensions from being pushed to the commit graph.")
      end

      sig { override.returns(T.nilable(String)) }
      def minimum_ghes_version
        "3.17"
      end

      sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:push]
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Array.new(name: "restricted_file_extensions", display_name: "Restricted file extensions", required: true, content_type: :string,
          description: "The file extensions that are restricted from being pushed to the commit graph.", ui_control: "file_extension_restriction",
          validator: method(:ensure_valid_file_extensions)))
        schema
      end

      sig { params(context: T.untyped, restricted_file_extensions: T.untyped, errors: T.untyped).void }
      def ensure_valid_file_extensions(context, restricted_file_extensions, errors)
        if restricted_file_extensions.count > 200
          return errors << {
            error_code: :too_many_entries,
            message: "Limit of 200 file extensions reached",
          }
        end
        restricted_file_extensions.each do |restricted_file_extension|
          unless restricted_file_extension.present?
            return errors << {
              error_code: :empty_extension,
              message: "File extension cannot be empty",
            }
          end
          unless restricted_file_extension.start_with?("*.")
            return errors << {
              error_code: :invalid_extension,
              message: "File extension must start with *.",
            }
          end
          if restricted_file_extension[1...].include?("\\") ||
                 restricted_file_extension[1...].include?("/") ||
                 restricted_file_extension[1...].include?("*")
            return errors << {
              error_code: :invalid_extension,
              message: "File extension cannot contain \\, /, or *",
            }
          end
          if restricted_file_extension.length > 200
            return errors << {
              error_code: :extension_too_long,
              message: "File extension is too long (maximum is 200 characters)",
            }
          end
        end
        errors
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_metadata_types
        [:blob]
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          candidate: MetadataSources::Types::Candidate,
        ).returns(EvaluationResult)
      end
      def evaluate_candidate(context, ref_update, rule_config, candidate)
        path = T.cast(candidate, MetadataSources::Types::BlobCandidate).path
        return EvaluationResult.new(candidate: candidate, success: true) unless path.present?

        rule_config.param("restricted_file_extensions").each do |restricted_file_extension|
          return EvaluationResult.failure(candidate: candidate) if File.fnmatch?("**/#{restricted_file_extension}", path, File::FNM_PATHNAME | File::FNM_CASEFOLD | File::FNM_DOTMATCH)
        end

        EvaluationResult.success(candidate: candidate)
      end

      sig do
        override.params(
          context: RuleEvaluationContext,
          ref_update: Git::Ref::Update,
          rule_config: RepositoryRuleConfiguration,
          violations: T::Array[Violation],
        )
        .returns(RuleRun)
      end
      def generate_evaluation_result(context, ref_update, rule_config, violations)
        return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

        RuleRun.failure(
          rule_config: rule_config,
          ref_update: ref_update,
          message: "Files cannot include restricted file extensions.",
          violations: violations.map do |violation|
            candidate = T.cast(violation.candidate, MetadataSources::Types::BlobCandidate)
            {
              candidate: T.must(candidate.path),
              commit_oid: candidate.commit_oid
            }
          end
        )
      end
    end
  end
end
