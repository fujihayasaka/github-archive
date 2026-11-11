# typed: true
# frozen_string_literal: true

class Wiki::PagesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :wiki

  SORT_TOP = "!!!!!!!!"

  def pages
    # FIXME: use better sorting
    @pages ||= wiki.pages.sort_by do |p|
      title = p.title

      title =~ /\Ahome\Z/i ? SORT_TOP : title.downcase
    end
  end
end
