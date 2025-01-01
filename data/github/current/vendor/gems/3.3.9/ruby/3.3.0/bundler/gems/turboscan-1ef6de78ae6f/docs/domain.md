# Key Domain Concepts #

* *Analysis*: A run of the analysis tool against a given revision of the
  repository. The results of an analysis are stored in a SARIF file, and
  represent occurrences of rule violations, with supporting evidence.
* *Configuration*: Analysis results are stored with the build/analysis
  configuration, which currently comprises the ref (branch), tool
  and category.
* *Configuration group*: Analyses are considered to have the same configuration
  group if they have the same origin (i.e. API upload / YAML workflow etc)
  and, for a YAML workflow, if the related workflow file is also the same.
* *Category*: String used to create different configurations for the same
  ref and tool combination.
* *Tip*: The most recent analysis results for a particular configuration.
* *Baseline* / *Baseline Analysis*: Normally used to describe a tip that is
  about to be replaced by some new analysis results and with which the
  new analysis can be compared to determine what's been fixed.
* *Delivery origin*: The source of an analysis. E.g API, Managed Analysis,
  YAML workflow etc.
* *Physical Alert*: A violation of a rule in a specific revision and
  configuration of the code. In SARIF, a physical alert is called a
  "Result".
* *(Logical) Alert*: A conceptual violation of a rule associated to
  one or more Physical Alerts. When talking about Alerts, we typically
  mean Logical Alerts.
* *Alert Grouping*: The process of determining which Physical Alerts
  should be identified with a particular Logical Alert.
* *Alert Diffing*: Comparing two sets of Logical Alerts to identify
  Alerts that exist in one set but not in the other (introduction,
  elimination). Diffing is used in various contexts such as
  Notifications and PR Checks. Logical alerts that are equivalent
  across the two sets are not necessarily identical because
  information like position might not coincide. Alert Diffing is currently
  only permitted with analysis results with the same configuration.
* *Alert Resolution*: User activity labeling a Logical Alert as not
  relevant. Typically includes a rationale annotation (e.g., "False
  Positive", "Used in tests", "Won't fix"). The annotation can be used
  to identify rules that are not precise (yield many "False
  Positives"). Note that we don't use the term "resolved" in the UI -
  we would just say "closed" instead - although the term "fixed" is
  used where appropriate
  ([related discussion](https://github.com/github/dsp-code-scanning/issues/688)).
* *Fixed alert*: A fixed alert is one for which code changes were made
  (or the analysis tool updated) such that it is no longer considered
  present.
* *Closed alert*: A closed alert is either resolved or fixed (see above).
* *Alert Collapsing*: Sometimes CodeQL produces multiple results for a
  single code location, for example if data flow query has found
  multiple sources and/or sinks. In this case these results should be
  collapsed into a single Physical Alert. Consider two results with
  messages:
  - "Bad data flows from A to B"
  - "Bad data flows from A to C"
  This should be a single Physical Alert with "Bad data flows from A
  to {B,C}" (it is left as an exercise to the UI developer to
  visualize the two choices).
* *Rule*: A check performed by the analysis tool. The same check can
  be implemented in various ways and evolve over time, yielding
  different results across revisions.
* *SARIF*: [*Static Analysis Results Interchange
  Format*](https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/sarif-v2.1.0-cs01.html)
* *Fingerprint*: A SARIF term indicating an artificial identifier used
  to track Physical Alerts across analysis. The standard recommends
  ([Appendix B](https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/sarif-v2.1.0-cs01.html#AppendixFingerprints))
  that a Fingerprint be constructed from information such as "the name
  of the tool that produced the result, the rule id, the file system
  path to the analysis target.".  Tools can include a "Partial
  Fingerprint" with each result to encode additional information that
  should be used by the system to compute a fingerprint.
* *Stable ID*: The term used in Turbo-Scan to indicate a SARIF
  Fingerprint. Initially, this is composed of "Rule id + file path +
  linehash", with linehash being a CodeQL-specific concept. [See
  initial discussion issue](https://github.com/github/dsp-code-scanning/issues/181)
* *Linehash*: A Partial Fingerprint computed by CodeQL.
* *Result Management System*: The SARIF term for a system like Turbo-Scan: "A
  software system that consumes the log files produced by analysis
  tools, produces reports that enable engineering teams to assess the
  quality of their software artifacts at a point in time and to
  observe trends in the quality over time, and performs functions such
  as filing bugs and displaying information about individual results."
* *Index Page* (UI): Page showing the list of all alerts for the repository.
* *Show Page* (UI): Page showing a single logical alert.
* *Classification*: A physical alert can be "classified". A
  classification indicates that the alert should be considered less
  interesting for some reason, for example because it is in a `vendor`
  directory. Alerts with one or more classifications should not be
  shown by default in the UI.
* *Archive*: To save on database storage, we store the data of older analyses in blob storage
  instead of the database. Archival is the process of extracting analysis data from the database
  and writing it to blob storage. By analysis data we mean related data like physical alerts,
  the actual analysis row (ts_analyses) will stay in the database. The goal is to archive all analyses that
  are not most_recent and older than 30 days.
* *Live analysis*: An analysis is live if its data is stored in the database. See archive.
* *Historic analysis*: An analysis is historic if its data is stored as a SARIF file in blob storage.
* *Outdated Analysis*: An analysis entry in the database that signifies that the corresponding configuration should be
  ignored when determining alert states, and does not reflect an actual analysis produced by a tool.
  An outdated analysis has the `outdated_at` flag set to `true`.
* *Enabled*: TurboScan defines Code Scanning as enabled if default setup is enabled, or a non-stale tip exists for the default branch of the repository. (Some additional conditions apply on the GitHub side. See [enablement state](https://github.com/github/code-scanning/blob/HEAD/docs/enablement-state.md) for more details.)
