# typed: false
# frozen_string_literal: true

module SignupHelper
  include FeatureFlagHelper
  SIGNUP_FORM_WHITESPACE = "3" # default Primer spacing between form field groups

  def multiple_answer_description(question)
    if question.max_acceptable_answers > 10
      "(check all that apply)"
    else
      "(Select up to #{question.max_acceptable_answers})"
    end
  end

  def survey_selection_tag_for_question_and_choice(question, choice)
    classes = ["sr-only hx_focus-input js-survey-answer-choice"]
    classes << "js-other-choice" if choice.other? && question.short_text == "user_role"

    if question.accept_multiple_answers?
      classes << "js-allow-multiple"

      check_box_tag("answers[#{question.id}][choices][]", choice.id, false,
                    id: "answers_#{question.id}_choice_#{choice.id}",
                    class: classes.join(" "),
                    "data-max-choices": question.max_acceptable_answers,
                    "data-question-short-text": question.short_text)
    else
      radio_button_tag("answers[#{question.id}][choice]", choice.id, false,
                       class: classes.join(" "),
                      "data-question-short-text": question.short_text)
    end
  end

  def show_team_signup_modal_flow?
    params[:plan].present?
  end

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

  def signup_plan_summary_subhead(text)
    content_tag(:div, text, class: "signup-plan-summary-subhead f6 text-uppercase color-fg-muted pb-2 mb-2 color-border-muted")
  end

  def survey_question_text(question)
    case question.short_text
    when "interests"
      "I am interested in:"
    when "level_of_experience"
      "How much programming experience do you have?"
    else
      question.text
    end
  end

  def survey_choice_title(choice)
    case choice.short_text
    when "developer"
      "None"
    when "researcher"
      "A little"
    when "student"
      "A moderate amount"
    when "project_manager"
      "A lot"
    when "role_engineer"
      "Software Engineer"
    when "role_student"
      "Student"
    when "role_product_manager"
      "Product Manager"
    when "role_ux_design"
      "UX & Design"
    when "role_data_analytics"
      "Data & Analytics"
    when "role_marketing_sales"
      "Marketing & Sales"
    when "role_teacher"
      "Teacher"
    when "role_other"
      "Other"
    end
  end

  #pretend short text is just a slug, ignore crazy things like "developer -> i don't program"
  def survey_choice_description(choice)
    case choice.short_text
    when "developer"
      "I don't program at all"
    when "researcher"
      "I'm new to programming"
    when "student"
      "I'm somewhat experienced"
    when "project_manager"
      "I'm very experienced"
    when "learn_coding"
      "Learn to code"
    when "learn_github"
      "Learn Git and GitHub"
    when "github_pages"
      "Create a website with GitHub Pages"
    when "contribute"
      "Find and contribute to open source"
    when "school_work"
      "School work and student projects"
    when "github_api"
      "Use the GitHub API"
    when "other"
      "Other"
    when "role_engineer"
      "I write code"
    when "role_student"
      "I go to school"
    when "role_product_manager"
      "I write specs"
    when "role_ux_design"
      "I draw interfaces"
    when "role_data_analytics"
      "I write queries"
    when "role_marketing_sales"
      "I look at charts"
    when "role_teacher"
      "I educate people"
    when "role_other"
      "I do my own thing"
    else
      choice.text
    end
  end

  def survey_choice_description_text_class(question)
    case question.short_text
    when "user_role", "level_of_experience"
      "text-bold mt-1"
    when "github_plans"
      "text-bold mt-3"
    when "interests"
    end
  end

  def survey_question_classes(question)
    case question.short_text
    when "user_role", "level_of_experience"
      "col-12 col-md-6"
    when "github_plans"
      "col-12 col-sm-6 col-md-4"
    when "interests"
    end
  end

  def survey_question_styles(question)
    case question.short_text
    when "user_role", "level_of_experience"
    when "github_plans"
      "height: 160px;"
    when "interests"
    end
  end

  def hide_survey_choice?(choice)
    %w(do_not_know_yet).include?(choice.short_text)
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
