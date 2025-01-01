# typed: true
# frozen_string_literal: true

module Forks
  module SelectMenuTestHelpers
    include GitHub::ComponentTestHelpers

    SELECTED_CHECKBOX_SELECTOR = "input[type=checkbox][checked]"
    DESELECTED_CHECKBOX_SELECTOR = "input[type=checkbox]:not(checked)"
    SELECTED_MENUITEM_SELECTOR = "a[aria-checked=true]"
    DESELECTED_MENUITEM_SELECTOR = "a[aria-checked=false]"
    SELECTOR_OPTIONS = { visible: false, normalize_ws: true }.freeze

    def assert_selected_option(*options)
      options.each do |option|
        assert_selector SELECTED_MENUITEM_SELECTOR, text: option, **SELECTOR_OPTIONS
      end
    end

    def refute_selected_option(*options)
      options.each do |option|
        refute_selector SELECTED_MENUITEM_SELECTOR, text: option, **SELECTOR_OPTIONS
        assert_selector DESELECTED_MENUITEM_SELECTOR, text: option, **SELECTOR_OPTIONS
      end
    end

    def refute_rendered_option(*options, expect_selected: nil)
      options.each do |option|
        refute_selector DESELECTED_MENUITEM_SELECTOR, text: option, **SELECTOR_OPTIONS
      end

      assert_selected_option expect_selected if expect_selected.present?
    end

    def assert_selected_checkbox(*options)
      options.each do |option|
        assert_selector SELECTED_CHECKBOX_SELECTOR, id: option.to_s.parameterize, **SELECTOR_OPTIONS
      end
    end

    def refute_selected_checkbox(*options)
      options.each do |option|
        refute_selector SELECTED_CHECKBOX_SELECTOR, id: option.to_s.parameterize, **SELECTOR_OPTIONS
      end
    end

    def assert_option_url_params(path, link_text)
      assert_selector "a[href^='#{path}']", text: link_text
    end

  end

  module FixtureHelpers
    def create_fork(root = @root_repo, options = {})
      fork_number = root.reload.forks_count

      unless :created_at.in?(options.keys)
        options[:created_at] = root.created_at + fork_number.minutes
      end

      unless :pushed_at.in?(options.keys)
        options[:pushed_at] = options[:created_at]
      end

      user_login = options[:forker] || "forker#{fork_number}"
      fork = FactoryBot.create(:fork_repository, forker: FactoryBot.create(:user, login: user_login), fork_repo: root)
      fork.update!(name: "#{root.name}-#{fork_number}")

      ExampleRepositories.example_repo :rebase_pull_request, fork
      options.each do |opt, value|
        case opt
        when :stargazers
          fork.update!(stargazer_count: value)
        when :with_pull_request
          if value
            create_pull_request(fork)
          end
        when :open_issues
          value.times { FactoryBot.create :issue, repository: fork }
        when :pushed_at
          fork.update!(pushed_at: value)
        when :created_at
          fork.update!(created_at: value)
        end
      end
      fork
    end

    def create_pull_request(fork)
      FactoryBot.create(:pull_request, :with_mergeable_head, repository: fork, user: fork.owner)
    end

    def path_resolver(**options)
      PathResolver.new(
        options.delete(:repo_name) || "repo",
        options.delete(:repo_owner_display_login) || "owner",
        Forks::SearchOptionsResolver.new(**options),
      )
    end
  end
end
