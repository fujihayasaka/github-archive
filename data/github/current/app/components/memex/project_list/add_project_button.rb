# typed: true
# frozen_string_literal: true

class Memex::ProjectList::AddProjectButton < ApplicationForm # rubocop:disable ViewComponent/ComponentsHaveUnitTests

  form do |new_memex_form|
    title = @is_template ? "template" : "project"

    new_memex_form.hidden(
      name: :title,
      value: @is_template ? MemexProject.default_user_template_title(@user) : MemexProject.default_user_title(@user)
    )

    new_memex_form.hidden(
      name: :is_template,
      value: @is_template
    )

    new_memex_form.hidden(
      name: :ui,
      value: @ui&.serialize
    )

    new_memex_form.submit(
      label: "New #{title}",
      name: :submit,
      scheme: :primary,
      test_selector: "new-#{title}-button",
      data: { turbo: false }
    )
  end

  sig { params(user: User, is_template: T.nilable(T::Boolean), ui: T.nilable(MemexStats::UIValues)).void }
  def initialize(user:, is_template: false, ui: nil)
    @user = user
    @is_template = T.let(is_template || false, T::Boolean)
    @ui = T.let(ui, T.nilable(MemexStats::UIValues))
  end

end
