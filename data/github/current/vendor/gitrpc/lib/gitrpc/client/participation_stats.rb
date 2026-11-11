# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    CONTRIBUTION_PERIOD = 52 # weeks


    # Public: Returns contribution statistics for the repository
    #
    # base_oid - the String oid of the commit from which we will commence walking the commit graph.
    # user_emails - An array<String> of the emails we should consider as belonging to the "owner" of the repository.
    # end_date - date for the end of the range over which we are retrieving these states. responds to `to_i`. Typically something like `Time.now`
    # weeks - Integer count of the number of weeks prior to the end_date we are including for this data. Defaults to CONTRIBUTION_PERIOD (52)
    #
    # Example:
    #
    # {
    #   "all" => {
    #     0 => 35
    #     1 => 2
    #     ...
    #     51 => 543
    #   },
    #   "owner" => {
    #     0 => 0
    #     1 => 1
    #     ...
    #     51 => 4
    #   }
    # }
    #
    #
    def participation_stats(base_oid, user_emails, end_date, weeks = CONTRIBUTION_PERIOD)
      send_message(:participation_stats, base_oid, user_emails, end_date.to_i, weeks)
    end
  end
end
