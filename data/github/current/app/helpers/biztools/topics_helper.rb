# typed: false
# frozen_string_literal: true

module Biztools
  module TopicsHelper
    def link_topic_names(names, delimiter: nil)
      names = if delimiter
        names.split(delimiter)
      else
        names
      end
      links = names.map do |name|
        link_to(name, "/topics/#{Topic.normalize(name)}", target: "_blank")
      end
      safe_join(links, ", ")
    end
  end
end
