# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  class FileserversView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelper

    attr_reader :sort

    def enterprise?
      GitHub.enterprise?
    end

    def sortable_header(key, direction, title, tip_name)
      if sort == key
        span_tag = helpers.octicon("chevron-#{direction}")
        helpers.safe_join([title, span_tag])
      else
        helpers.link_to \
          title,
          urls.stafftools_fileservers_path(sort: key),
          class: "Link--muted tooltipped tooltipped-s",
          "aria-label": "Click to sort by #{tip_name}"
      end
    end
  end
end
