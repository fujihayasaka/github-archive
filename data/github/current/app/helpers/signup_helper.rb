# typed: false
# frozen_string_literal: true

module SignupHelper
  include FeatureFlagHelper
  SIGNUP_FORM_WHITESPACE = "3" # default Primer spacing between form field groups

  def signup_h1(text, **options)
    content_tag(:h1, text, class: "d-md-block mt-0 mb-3 text-center h1 lh-condensed-ultra #{options.delete(:class)}", **options)
  end

  def signup_h2(text, **options)
    content_tag(:h2, text, class: "f4 #{options.delete(:class)}", **options)
  end

  def signup_form_margin(direction = "")
    "m#{direction}-#{SIGNUP_FORM_WHITESPACE}"
  end

  def signup_progress(text:)
    content_tag(:div, text, class: "text-mono text-center color-fg-muted text-normal mb-1")
  end

  def primary_password_field_confirmation_class
    if GitHub.password_confirmation_required?
      "js-password-with-confirmation"
    end
  end

  def publish_billing_plan_changed_for(actor:,
                                       user:,
                                       new_seat_count: 0,
                                       old_seat_count: 0,
                                       old_plan_name: "",
                                       new_plan_name:,
                                       user_first_name: "",
                                       user_last_name: "")
    GlobalInstrumenter.instrument(
      "billing.plan_change",
      actor_id: actor.id,
      user_id: user.id,
      old_plan_name: old_plan_name,
      old_seat_count: old_seat_count,
      new_plan_name: new_plan_name,
      new_seat_count: new_seat_count,
      user_first_name: user_first_name,
      user_last_name: user_last_name,
    )
  end

  def show_plan_upgrade_on_invite_page?
    !Billing::EnterpriseCloudTrial.new(current_organization).active?
  end

  def get_started_cta_details
    [
      {
        title: "Start a new project",
        description: "Start a new repository or bring over an existing repository to keep contributing to it.",
        button_text: "Create a repository",
        button_link: new_repository_path,
        svg_path: "modules/signup/interstitial/engineering.svg",
        svg_dark_path: "modules/signup/interstitial/engineering_dark.svg",
        event_type: :create_repo,
      },
      {
        title: "Collaborate with your team",
        description: "Improve the way your team works together and get access to more features with an organization.",
        button_text: "Create an organization",
        button_link: organizations_new_path,
        svg_path: "modules/signup/company.svg",
        svg_dark_path: "modules/signup/company_dark.svg",
        event_type: :create_org,
      },
      {
        title: "Learn how to use GitHub",
        description: "Get started with an \"Introduction to GitHub\" course in GitHub Skills.",
        button_text: "Start Learning",
        button_link: "https://skills.github.com/",
        svg_path: "modules/signup/interstitial/editor-tools.svg",
        svg_dark_path: "modules/signup/interstitial/editor-tools_dark.svg",
        event_type: :learning_lab,
      },
    ]
  end
end
