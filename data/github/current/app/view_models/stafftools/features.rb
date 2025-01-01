# typed: true
# frozen_string_literal: true

module Stafftools
  module Features
    include ActionView::Helpers::UrlHelper
    URL_HELPERS = UrlHelpers

    def feature_link(feature, show_percentage_of_time:)
      link = ActionController::Base.helpers.link_to(feature.name, URL_HELPERS.devtools_feature_flag_path(feature))

      if show_percentage_of_time && feature.percentage_of_time_value > 0
        ActionController::Base.helpers.safe_join([link, " @ #{feature.percentage_of_time_value}%"])
      else
        link
      end
    end

    # Returns hash with features by gate type
    # Hash values are an Array of Arrays: [[FlipperFeature, Link]]
    def enabled_feature_flags_by_gate_type(actor)
      FlipperFeature.all.each_with_object({ actor_gates: [], possibly_gates: [], inherited_gates: [] }) do |feature, features|
        gates = feature.open_gates(actor)
        next unless gates.any?
        if gates.all? { |f| f.key == :actors } # these gates can be removed with effect.
          features[:actor_gates] << [feature, feature_link(feature, show_percentage_of_time: false)]
        elsif gates.any? { |f| f.key == :percentage_of_time && feature.percentage_of_time_value > 0 }
          features[:possibly_gates] << [feature, feature_link(feature, show_percentage_of_time: true)]
        else
          features[:inherited_gates] << [feature, feature_link(feature, show_percentage_of_time: false)]
        end
      end
    end

  end
end
