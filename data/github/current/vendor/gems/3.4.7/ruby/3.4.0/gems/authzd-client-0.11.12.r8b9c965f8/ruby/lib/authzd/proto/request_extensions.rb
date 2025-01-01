# frozen_string_literal: true

module Authzd::Proto
  class Request
    def rpc_name
      "authorize"
    end

    def batch?
      false
    end
  end
end

module Authzd::CapEvaluator
  class SingleResourceRequest
    def rpc_name
      "evaluate_policies_for_single_resource"
    end

    def batch?
      false
    end
  end

  class FilterRequest
    def rpc_name
      "evaluate_policies_for_filtering"
    end

    def batch?
      false
    end
  end
end

module Authzd::Enumerator
  class ForSubjectRequest
    def rpc_name
      "for_subject"
    end

    def batch?
      false
    end
  end

  class ForActorRequest
    def rpc_name
      "for_actor"
    end

    def batch?
      false
    end
  end
end

module Authzd::ControlAccess
  class Request
    def rpc_name
      "check"
    end
  end
end
