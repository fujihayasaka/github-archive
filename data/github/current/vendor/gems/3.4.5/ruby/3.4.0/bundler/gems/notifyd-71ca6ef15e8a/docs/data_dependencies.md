# `notifyd` data dependencies

In order to perform its work, `notifyd` relies on a number of different types
of data to derive decisions from. This data is in part stored in its own
database and managed by `notifyd`, but there are also other data that comes
from remote sources. In terms of availability, any of those data sources not
being available/reliable means a failure in `notifyd` message processing.


| Type of Data | Source | Storage Location |
|--------------|--------|------------------|
| User notification Settings | [monolith-twirp-api][cat-twirp] | mysql2 |
| Notification eligibility (batch check policy) | [monolith-twirp-api][cat-twirp]| several (mysql2, ...) |
| Recipient policies | [authzd][cat-authzd] | db-authzd |
| Rendered Email templates | [monolith-twirp-api][cat-twirp] | - |
| Subscriptions | [notifyd][cat-notifyd] | notifyd DB |
| Routing Settings | [notifyd][cat-notifyd] | notifyd DB |
| Mobile Deliveries | [notifyd][cat-notifyd] | notifyd DB |
| Mobile Device Tokens | [notifyd][cat-notifyd] | notifyd DB |





[cat-twirp]: https://catalog.githubapp.com/services/github/twirp_api/
[cat-notifyd]: https://catalog.githubapp.com/services/notifyd/
[cat-authzd]: https://catalog.githubapp.com/services/authzd
