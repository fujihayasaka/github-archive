# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # CurrentViewerFilter matches <gh:current-viewer-reference> elements and performs authorization checks
  # based only on attributes or methods on the current viewing user.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call current_viewer_reference_wrapper, e.g.
  #
  # class MyFilter < NodeFilter
  #   include GitHub::Goomba::Reference::Helpers
  #   def call(node)
  #     # return an authorization wrapper that the Authorization::CurrentViewerFilter will use to check whether the
  #     # viewer is an employee, and includes the content that authorized and unauthorized viewers should see
  #     current_viewer_reference_wrapper(employee: true) do |wrapper|
  #       wrapper.authorized { "I'm an employee and can see #{node.to_html}" }
  #       wrapper.unauthorized { "I'm not an employee and cannot see the original content" }
  #     end
  #   end
  # end
  class CurrentViewerFilter < ReferenceFilter
    ELEMENT = "gh:current-viewer-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    def selector
      SELECTOR
    end

    def async_check_authorization(nodes)
      check_employee(nodes)

      Promise.resolve
    end

    private

    # Check whether a viewer should see content based on whether the current user is an employee
    def check_employee(nodes)
      return if nodes.empty?

      is_employee = current_user&.employee?
      nodes.each do |node|
        case node["employee"]
        when "true"
          authorized_nodes << node if is_employee
        else
          authorized_nodes << node
        end
      end
    end
  end
end
