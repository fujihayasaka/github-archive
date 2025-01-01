# typed: strict
# frozen_string_literal: true

class CopilotOrcaMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_orca"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(pipeline_id: String).returns(String) }
  def model_ready(pipeline_id)
    pipeline = T.must(Orca::Pipeline.fetch_by_id(pipeline_id))
    @org = T.let(pipeline.organization, T.nilable(Organization))
    actor = pipeline.actor

    @pipeline_id = T.let(pipeline_id, T.nilable(String))
    subject = "[GitHub] [#{T.must(@org).safe_profile_name}] Custom model training ready"

    if T.must(@org).feature_flag_enabled_or_raise?(:copilot_custom_models_email_all_admins) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      premail(
        from: github_noreply,
        bcc: admin_emails(@org),
        subject: subject,
      )
    else
      premail(
        from: github_noreply,
        to: user_email(actor),
        subject: subject,
      )
    end
  end

  sig { params(pipeline_id: String).returns(String) }
  def model_failed(pipeline_id)
    pipeline = T.must(Orca::Pipeline.fetch_by_id(pipeline_id))
    actor = pipeline.actor
    @org = pipeline.organization

    @pipeline_id = pipeline_id
    subject = "[GitHub] [#{@org.safe_profile_name}] Custom model training failed"

    if @org.feature_flag_enabled_or_raise?(:copilot_custom_models_email_all_admins) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      premail(
        from: github_noreply,
        bcc: admin_emails(@org),
        subject: subject,
      )
    else
      premail(
        from: github_noreply,
        to: user_email(actor),
        subject: subject,
      )
    end
  end

  sig { params(pipeline_id: String).returns(String) }
  def access_granted(pipeline_id)
    pipeline = T.must(Orca::Pipeline.fetch_by_id(pipeline_id))
    actor = pipeline.actor
    @org = pipeline.organization

    subject = "[GitHub] You have been granted access to a custom model"

    if @org.feature_flag_enabled_or_raise?(:copilot_custom_models_email_all_admins) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      premail(
        from: github_noreply,
        bcc: admin_emails(@org),
        subject: subject,
      )
    else
      premail(
        from: github_noreply,
        to: user_email(actor),
        subject: subject,
      )
    end
  end

  sig { params(pipeline_id: String).returns(String) }
  def model_deleted(pipeline_id)
    pipeline = T.must(Orca::Pipeline.fetch_by_id(pipeline_id))
    actor = pipeline.actor
    @org = pipeline.organization

    subject = "[GitHub] Custom model deleted"

    if @org.feature_flag_enabled_or_raise?(:copilot_custom_models_email_all_admins) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      premail(
        from: github_noreply,
        bcc: admin_emails(@org),
        subject: subject,
      )
    else
      premail(
        from: github_noreply,
        to: user_email(actor),
        subject: subject,
      )
    end
  end

  sig { params(pipeline_id: String).returns(String) }
  def update_ready(pipeline_id)
    pipeline = T.must(Orca::Pipeline.fetch_by_id(pipeline_id))
    actor = pipeline.actor
    @org = pipeline.organization
    @pipeline_id = T.let(pipeline_id, T.nilable(String))

    subject = "[GitHub] [#{@org.safe_profile_name}] Custom model training update ready"

    if @org.feature_flag_enabled_or_raise?(:copilot_custom_models_email_all_admins) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      premail(
        from: github_noreply,
        bcc: admin_emails(@org),
        subject: subject,
      )
    else
      premail(
        from: github_noreply,
        to: user_email(actor),
        subject: subject,
      )
    end
  end

  # Needed for logging
  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    @org
  end
end
