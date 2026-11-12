# frozen_string_literal: true

module HasSeverities
  delegate :severities, to: :AdvisoryDB
  delegate :severity_label, to: :AdvisoryDB
  delegate :severity_color, to: :AdvisoryDB
  delegate :severity_scheme, to: :AdvisoryDB
end
