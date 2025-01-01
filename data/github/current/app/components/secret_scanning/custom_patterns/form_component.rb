# typed: true
# frozen_string_literal: true

require "json"

module SecretScanning
  module CustomPatterns
    class FormComponent < ApplicationComponent
      include SecurityAnalysisSettingsHelper
      include SecretScanningCustomPatternsHelper
      include SecretScanning::Features::FeatureFlagHelper

      attr_reader :pattern, :owner, :mode, :settings_path, :submit_path, :update_custom_pattern_settings_path, :test_pattern_path, :remove_pattern_path, :publish_alert_message, :dry_run_info, :cancel_custom_pattern_dry_run_path, :form_actions_path, :get_alert_metrics_path, :get_push_protection_metrics_path, :get_generated_expressions_path, :error_message

      def initialize(
        pattern:,
        owner:,
        mode:,
        settings_path:,
        submit_path:,
        update_custom_pattern_settings_path: nil,
        test_pattern_path:,
        remove_pattern_path:,
        show_publish_alert_message:,
        dry_run_info:,
        cancel_custom_pattern_dry_run_path:,
        form_actions_path:,
        get_alert_metrics_path:,
        get_push_protection_metrics_path:,
        error_message: nil,
        get_generated_expressions_path: nil
      )
        @pattern = pattern
        @owner = owner
        @mode = mode
        @settings_path = settings_path
        @submit_path = submit_path
        @update_custom_pattern_settings_path = update_custom_pattern_settings_path
        @test_pattern_path = test_pattern_path
        @remove_pattern_path = remove_pattern_path
        @show_publish_alert_message = show_publish_alert_message
        @dry_run_info = dry_run_info
        @cancel_custom_pattern_dry_run_path = cancel_custom_pattern_dry_run_path
        @form_actions_path = form_actions_path
        @get_alert_metrics_path = get_alert_metrics_path
        @get_push_protection_metrics_path = get_push_protection_metrics_path
        @error_message = error_message
        @get_generated_expressions_path = get_generated_expressions_path
      end

      def header_text
        case mode
        when :create
          return "New custom pattern"
        when :edit, :published
          return "Update pattern"
        when :unpublished
          return "Unpublished pattern"
        end

        "Custom pattern"
      end

      def settings_path_text
        if owner.present?
          return "Custom patterns" if owner.is_a?(Business)
          return "Global settings" if owner.is_a?(Organization)
        end

        "Advanced Security"
      end

      def form_submit_url
        return @cancel_custom_pattern_dry_run_path if SecretScanningCustomPatternsHelper::allow_dry_run_cancellation?(@mode, current_dry_run_status)
        @submit_path
      end

      sig { returns(T::Boolean) }
      def show_push_protection_options?
        @pattern.present? && @mode == :published && @update_custom_pattern_settings_path.present?
      end

      sig { returns(T::Boolean) }
      def show_push_protection_warning?
        is_repo_scope? && !@pattern.push_protection_enabled && !push_protection_enabled_for_repo?
      end

      @memoized
      def push_protection_enabled_for_repo?
        is_repo_scope? && SecretScanning::Features::Repo::PushProtection.new(@owner).enabled?
      end

      @memoized
      sig { returns(T::Boolean) }
      def generate_expressions_with_ai_sidebar_enabled?
        if @owner.is_a?(Repository)
          return SecretScanning::Features::Repo::CustomPatterns.new(@owner).generate_expressions_with_ai_enabled?
        elsif @owner.is_a?(Organization)
          return SecretScanning::Features::Org::CustomPatterns.new(@owner).generate_expressions_with_ai_enabled?
        elsif @owner.is_a?(Business)
          return SecretScanning::Features::Business::CustomPatterns.new(@owner).generate_expressions_with_ai_enabled?
        end

        false
      end

      sig { returns(String) }
      def repository_settings_url
        return "" unless is_repo_scope?
        security_analysis_settings_path(owner)
      end

      def render_custom_pattern_push_protection_btn
        if @pattern.push_protection_enabled
          render(Primer::Beta::Button.new(name: "push_protection_enabled", value: false, scheme: :danger, type: :submit, data: { test_selector: "disable-push-protection-btn" })) { "Disable" }
        else
          render(Primer::Beta::Button.new(name: "push_protection_enabled",
            value: true,
            type: :submit,
            disabled: is_repo_scope? && !push_protection_enabled_for_repo?,
            data: { test_selector: "enable-push-protection-btn" })) { "Enable" }
        end
      end

      def current_dry_run_status
        SecretScanningCustomPatternsHelper::dry_run_status(@dry_run_info)
      end

      def allow_pattern_delete?
        return true unless mode == :create

        false
      end

      def display_publish_alert_message?
        return false unless @show_publish_alert_message
        mode == :unpublished if current_dry_run_status == :COMPLETED
      end

      # Returns true if the pattern already exists, i.e. we are
      # either viewing dry run status in unpublished mode, or
      # modifying the pattern in edit mode.
      def pattern_created?
        mode != :create
      end

      sig { returns(T::Boolean) }
      def pattern_published?
        @mode == :published
      end

      def display_name_label
        label = "Pattern name"

        return label + " *" if @mode == :create
        label
      end

      def display_name_edit_message
        if mode == :create
          return "This cannot be edited after saving."
        end

        nil
      end

      def disable_pattern_fields?
        if show_dry_run_section?
          if current_dry_run_status == :QUEUED || current_dry_run_status == :INPROGRESS
            return true
          end
        end

        false
      end

      def show_dry_run_section?
        mode == :unpublished || mode == :published
      end

      def display_name
        return @pattern.display_name unless @pattern.nil?

        ""
      end

      # Specifies a custom width for the display name input field - this is intentionally shorter than the other fields for design reasons.
      def display_name_field_style
        "max-width: 436px;"
      end

      def expression
        return @pattern.expression unless @pattern.nil?

        ""
      end

      def start_delimiter
        return @pattern.post_processing.start_delimiter unless @pattern.nil?

        default_start_delimiter
      end

      def end_delimiter
        return @pattern.post_processing.end_delimiter unless @pattern.nil?

        default_end_delimiter
      end

      def default_start_delimiter
        "\\A|[^0-9A-Za-z]"
      end

      def default_end_delimiter
        "\\z|[^0-9A-Za-z]"
      end

      def post_processing_must_match
        return @pattern.post_processing.must_match unless @pattern.nil?

        []
      end

      def post_processing_must_not_match
        return @pattern.post_processing.must_not_match unless @pattern.nil?

        []
      end

      def pattern_id
        @pattern.id
      end

      memoize def dry_run_selected_repo_ids_json
        selected_repo_ids = get_dry_run_selected_repo_ids
        return nil if selected_repo_ids.nil?
        selected_repo_ids.to_json
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      memoize def get_dry_run_selected_repo_ids
        return [] if @pattern.nil? || @owner.nil? || @pattern.scope == :repo_scope || @owner.is_a?(Repository)
        # Convert from Google::Protobuf::RepeatedField to ruby Array
        selected_repo_ids = @pattern.dry_run_repositories.to_a
        SecretScanning::Services::CustomPatternsService.new(current_user).valid_repositories(@pattern.created_by_id, @owner, selected_repo_ids)
      end

      def force_disable_primary_button?
        return true unless @mode == :unpublished || @mode == :published
        current_dry_run_status == :PENDING
      end

      sig { returns(T::Boolean) }
      def web_socket_enabled?
        @mode == :unpublished || @mode == :published
      end

      sig { returns(T::Boolean) }
      def is_repo_scope?
        @owner.is_a?(Repository)
      end

      sig { returns(T::Boolean) }
      def show_metrics?
        self.pattern_created?
      end

      sig { returns(T::Boolean) }
      def show_wildcard_warning?
        flash[:show_wildcard_warning] == true
      end
    end
  end
end
