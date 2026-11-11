# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class FilePathRestrictionRule < CommitRule
      include Scientist

      sig { void }
      def initialize
        super(rule_name: "file_path_restriction",
              display_name: "Restrict file paths",
              description: "Prevent commits that include changes in specified file and folder paths from being pushed to the commit graph. This includes absolute paths that contain file names.")
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
        schema.add_field(ParameterSchema::Array.new(name: "restricted_file_paths", display_name: "Restricted file paths", required: true, content_type: :string,
          description: "The file paths that are restricted from being pushed to the commit graph.", ui_control: "file_path_restriction",
          validator: method(:ensure_valid_path_patterns)))
        schema
      end

      sig { params(context: T.untyped, restricted_file_paths: T.untyped, errors: T.untyped).void }
      def ensure_valid_path_patterns(context, restricted_file_paths, errors)
        if restricted_file_paths.count > 200
          return errors << {
            error_code: :too_many_entries,
            message: "Limit of 200 file paths reached",
          }
        end
        # check each element in the array to ensure it's not empty
        restricted_file_paths.each do |restricted_path|
          unless restricted_path.present?
            return errors << {
              error_code: :empty_path,
              message: "File path cannot be empty"
            }
          end

          if restricted_path.length > 200
            errors << {
              error_code: :path_too_long,
              message: "File path is too long (maximum is 200 characters)"
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
        restricted_file_paths = rule_config.parameters["restricted_file_paths"]
        return EvaluationResult.success(candidate: candidate) unless restricted_file_paths.present? # if empty array, then no restrictions

        candidate_path = T.cast(candidate, MetadataSources::Types::BlobCandidate).path
        return EvaluationResult.new(candidate: candidate, success: true) unless candidate_path.present?

        violated_restrictions = restricted_file_paths.filter { |restricted_pattern| File.fnmatch?(restricted_pattern, candidate_path, File::FNM_PATHNAME | File::FNM_CASEFOLD | File::FNM_DOTMATCH) }

        if violated_restrictions.present?
          EvaluationResult.new(candidate: candidate, success: false, metadata: { violated_restrictions: })
        else
          EvaluationResult.new(candidate: candidate, success: true)
        end
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
          message: "File path is restricted",
          violations: violations.map do |violation|
            candidate = T.cast(violation.candidate, MetadataSources::Types::BlobCandidate)
            {
              candidate: T.must(candidate.path),
              commit_oid: candidate.commit_oid,
              violated_restrictions: violation.metadata&.[](:violated_restrictions),
            }
          end
        )
      end
    end
  end
end
