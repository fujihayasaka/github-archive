#!/usr/bin/env ruby

require_relative "../../config/environment"

TRUNCATED_LICENSES = [
  "(Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND EPL-1.0 AND EPL-2.0 AND GPL-2.0) OR (Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND EPL-1.0 AND EPL-2.0 AND LGPL-2.1) OR (Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND EPL-1.0 AND EPL-2.0) OR ...",
  "(Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND FTL AND GPL-2.0-only AND GPL-3.0-only AND IJG AND ImageMagick AND JasPer-2.0 AND LGPL-2.0-only AND LGPL-2.1-only) OR (Apache-2.0 AND CDDL-1.0 AND LGPL-2.1-or-later AND LGPL-3.0-only AND Libpng AND ...",
  "(CPL-1.0 AND EPL-1.0 AND GPL-1.0-or-later AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (CPL-1.0 AND GPL-1.0-or-later AND GPL-2.0 AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (CPL-1.0 AND GPL-1.0-or-later AND GPL-2.0-only AN",
  "(EPL-1.0 AND EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0 AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0-only AN",
  "(EPL-1.0 AND EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0 AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0...",
  "(EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0 AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2.0-only AND LGPL-2.0-or-later AND LGPL-2.1 AND LGPL-2.1-only) OR (EPL-2.0 AND GPL-1.0-or-later AND GPL-2....",
  "(GPL-2.0 AND GPL-2.0-only AND GPL-3.0-only AND Ruby) OR (GPL-2.0 AND GPL-2.0-only AND Ruby) OR (GPL-2.0 AND GPL-3.0-only AND Ruby) OR (GPL-2.0 AND GPL-3.0-only) OR (GPL-2.0-only AND GPL-3.0 AND GPL-3.0-only AND Ruby) OR (GPL-2.0-only AND GPL-3.0 A...",
  "(GPL-2.0 AND GPL-2.0-only AND GPL-3.0-only AND Ruby) OR (GPL-2.0 AND GPL-2.0-only) OR (GPL-2.0 AND GPL-3.0-only) OR (GPL-2.0-only AND GPL-3.0 AND GPL-3.0-only AND Ruby) OR (GPL-2.0-only AND GPL-3.0) OR (GPL-2.0-only AND GPL-3.0-only AND NOASSERTIO...",
  "MPL-1.1 OR (GPL-2.0 AND GPL-2.0-or-later) OR (GPL-2.0 AND LGPL-2.1-or-later) OR (GPL-2.0 AND MPL-1.1) OR (GPL-2.0-or-later AND LGPL-2.1) OR (GPL-2.0-or-later AND MPL-1.1) OR (LGPL-2.1 AND LGPL-2.1-or-later) OR (LGPL-2.1 AND MPL-1.1) OR (LGPL-2.1-o..."
]

rows_updated = 0

ActiveRecord::Base.connected_to(role: :writing) do
  PackageRelease.where(license: TRUNCATED_LICENSES).in_batches(of: 20) do |batch|
    rows_updated += batch.update(license: "NOASSERTION").count
  end
end

puts "Completed: #{rows_updated} package releases updated."
