# typed: true
# frozen_string_literal: true

class Businesses::Organizations::Settings::RowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organizations

  def initialize(**args)
    super(args)

    @organizations = args[:organizations]
    @first_number_of_orgs = args[:first_number_of_orgs]
  end

  def total_count
    @organizations.count
  end

  def hidden_count
    [0, total_count - first_number_of_orgs].max
  end

  def summary_text
    return "0 organizations" if organizations.empty?

    parts = organizations.first(first_number_of_orgs).map(&:name)
    parts << helpers.pluralize(hidden_count, "other") if hidden_count > 0
    parts.to_sentence
  end

  def count_text
    "#{total_count} #{"organization".pluralize(total_count)}"
  end

  def first_number_of_orgs
    @first_number_of_orgs ||= 37
  end
end
