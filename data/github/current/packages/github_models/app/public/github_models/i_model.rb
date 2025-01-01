# typed: strict
# frozen_string_literal: true

module GitHubModels
  # Public: Represents an AI model available in GitHub Models.
  module IModel
    extend T::Helpers

    include Kernel
    include DefaultAndCustomModels::IModel

    interface!

    sig { abstract.returns(Types::FeaturedModel) }
    def to_featured_model; end

    sig { abstract.returns(T.nilable(GitHubModels::Types::OrganizationAccessPolicyShowModel)) }
    def to_organization_access_policy_show_model; end

    sig { abstract.returns(T.nilable(String)) }
    def training_data_date; end

    sig { abstract.returns(String) }
    def source; end

    sig { abstract.returns(T.nilable(String)) }
    def version; end

    sig { abstract.returns(T.nilable(String)) }
    def evaluation; end

    sig { abstract.returns(T.nilable(String)) }
    def summary; end

    sig { abstract.returns(T.nilable(String)) }
    def notes; end

    sig { abstract.returns(T.nilable(String)) }
    def description; end

    sig { abstract.returns(T.nilable(String)) }
    def license; end

    sig { abstract.returns(T.nilable(String)) }
    def license_description; end

    sig { abstract.returns(T.nilable(String)) }
    def rate_limit_tier; end

    sig { abstract.returns(T.nilable(Integer)) }
    def max_input_tokens; end

    sig { abstract.returns(T.nilable(Integer)) }
    def max_output_tokens; end

    sig { abstract.returns(T.nilable(String)) }
    def publisher; end

    sig { abstract.params(publisher_name: T.nilable(String)).returns(T::Boolean) }
    def publisher_matches?(publisher_name); end

    sig { abstract.returns(T.nilable(Integer)) }
    def models_publisher_id; end

    sig { abstract.returns(T.nilable(Publisher)) }
    def models_publisher; end

    sig { abstract.params(dark_mode: T::Boolean).returns(T.nilable(String)) }
    def icon_src(dark_mode:); end

    sig { abstract.returns(T::Array[String]) }
    def supported_languages; end

    sig { abstract.returns(T::Array[String]) }
    def tags; end

    sig { abstract.returns(T::Array[String]) }
    def supported_input_modalities; end

    sig { abstract.returns(T::Array[String]) }
    def supported_output_modalities; end

    sig { abstract.returns(T::Array[String]) }
    def catalog_capabilities; end

    sig { abstract.returns(Integer) }
    def popularity; end

    sig { abstract.returns(String) }
    def details_path; end

    sig { abstract.returns(String) }
    def visibility; end

    sig { abstract.returns(T.nilable(String)) }
    def dark_mode_icon; end

    sig { abstract.returns(T.nilable(String)) }
    def light_mode_icon; end

    sig { abstract.returns(T.nilable(String)) }
    def external_id; end

    sig { abstract.returns(T::Boolean) }
    def chat_completion?; end

    sig { abstract.returns(T::Boolean) }
    def restricted?; end

    sig { abstract.returns(String) }
    def downcased_external_slug; end
  end
end
