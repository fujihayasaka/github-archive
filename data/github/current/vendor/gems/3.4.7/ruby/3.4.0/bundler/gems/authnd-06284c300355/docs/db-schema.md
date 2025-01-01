# Tables

## oauth_accesses
### Description
Stores user-to-server OAuth Access tokens (PATs or tokens for OAuth Applications or GitHub apps).

### Schema
| Column                    | Type          | Nullable    |
| ------------------------- | ------------- | ----------- |
| id                        | int           | not null    |
| user_id                   | int           | not null    |
| application_id            | int           | not null    |
| created_at                | datetime      | null        |
| updated_at                | datetime      | null        |
| accessed_at               | datetime      | null        |
| hashed_token              | varbinary(44) | null        |
| token_last_eight          | varchar(8)    | null        |
| authorization_id          | int           | null        |
| application_type          | varchar(16)   | null        |
| expires_at_timestamp      | bigint        | null        |

### Indexes and Unique Constraints
- `index_oauth_accesses_on_hashed_token`: Index on `hashed_token`

### Column Details
- `id`: We are using the same primary key identifier as `mysql1`. Note, this field is not autoincremented in authnd.
- `user_id`: The dotcom user id to which this token is assigned.
- `application_id`: `0` if the token is a PAT. Otherwise it references `oauth_applications.id` if the token is for an OAuth Application or `integrations.id` this is for a GitHub App.
- `accessed_at`: The date the token was last used.
- `hashed_token`: Represents the token which has been hashed. This the field on which authnd queries user-to-server tokens - by hashing the request input and querying by this column.
- `token_last_eight`: The last eight characters of the raw token.
- `authorization_id`: References `oauth_authorizations.id`. Each `oauth_access` has one `oauth_authorization`, which contains its scopes.
- `application_type`: `OauthApplication` if it is a PAT or user-to-server oauth access token for an OAuth Application, or `Integration` if it is a user-to-server oauth access token for a GitHub application.
- `expires_at_timestamp`: The unix timestamp at which this token will expire.

## oauth_applications
### Description
Stores OAuth Application details.

### Schema
| Column                    | Type          | Nullable    |
| ------------------------- | ------------- | ----------- |
| id                        | int           | not null    |
| name                      | int           | null        |
| user_id                   | int           | null        |
| created_at                | datetime      | null        |
| updated_at                | datetime      | null        |
| state                     | int           | null        |

### Indexes and Unique Constraints
- `index_oauth_applications_on_user_id`: Index on `user_id`

### Column Details
- `id`: We are using the same primary key identifier as `mysql1`. Note, this field is not autoincremented in authnd.
- `name`: The human readable name of the OAuth Application.
- `user_id`: The dotcom user id that owns this OAuth Application.
- `state`: An enumeration that indicates if the OAuth Application is suspended (`state = 1`) or not (`state = (anything else)`).

## organization_credential_authorizations
### Description
Tracks whether a credential has been granted access to an organization.

### Schema
| Column                    | Type          | Nullable    |
| ------------------------- | ------------- | ----------- |
| id                        | int           | not null    |
| organization_id           | int           | not null    |
| credential_id             | int           | not null    |
| credential_type           | varchar(30)   | not null    |
| created_at                | datetime      | not null    |
| updated_at                | datetime      | not null    |
| revoked_at                | datetime      | null        |
| revoked_by_id             | int           | null        |

### Indexes and Unique Constraints
- `index_on_credential_id_and_credential_type`: Index on `credential_id`, `credential_type`

### Column Details
- `id`: We are using the same primary key identifier as `mysql1`. Note, this field is not autoincremented in authnd.
- `organization_id`: The organization to which a credential has been granted access.
- `credential_id`: The credential id to which to restrict to an organization.
- `credential_type`: The type of credential. A credential can be a PAT or an oauth access token. It currently is not, but this can be expanded to include other models such as public keys.
- `revoked_at`: Date organization access grant was revoked.
- `revoked_by_id`: The id of the user that revoked the organization access.

## public_keys
### Description
Stores SSH Public Keys.

### Schema
| Column                    | Type          | Nullable    |
| ------------------------- | ------------- | ----------- |
| id                        | int           | not null    |
| key                       | text          | not null    |
| fingerprint               | varbinary(64) | not null    |
| title                     | varchar(255)  | not null    |
| actor_id                  | int           | not null    |
| actor_type                | tinyint(1)    | not null    |
| verified_at               | datetime      | null        |

### Indexes and Unique Constraints
- `index_public_keys_on_fingerprint`: UNIQUE index on `fingerprint`

### Column Details
- `id`: We are using the same primary key identifier as `mysql1`. Note, this field is not autoincremented in authnd.
- `key`: The full ssh public key.
- `fingerprint`: Hash used to look up the ssh public key.
- `title`: A human readable title for the ssh public key.
- `actor_id`: The primary key of the `user` or `repository` for which the public key applies.
- `actor_type`: `user` or `repository`.
- `verified_at`: The date the ssh public key was verified.

## users
### Description
Stores users and organizations.

### Schema
| Column                    | Type          | Nullable    |
| ------------------------- | ------------- | ----------- |
| id                        | int           | not null    |
| bcrypt_auth_token         | varchar(60)   | null        |
| password_hash             | varbinary(127)| null        |
| weak_password_check_result| varbinary(128)| null        |
| token_secret              | varchar(40)   | null        |
| created_at                | datetime      | null        |
| updated_at                | datetime      | null        |
| suspended_at              | datetime      | null        |
| disabled                  | tinyint(1)    | null        |

### Indexes and Unique Constraints
- `index_users_on_login`: UNIQUE index on `login`.

### Column Details
- `id`: We are using the same primary key identifier as `mysql1`. Note, this field is not autoincremented in authnd.
- `bcrypt_auth_token`: Legacy column used to store user passwords using bcrypt. When authenticating by username/password, we may need to conditionally look at this column if `password_hash` is not populated. (Need to examine what dotcom is currently doing).
- `password_hash`: This is the newest column we use for username/pw auth. It’s stored in the linux etc password format. Example: `$argon2id$v=19$m=16,t=1,p=1$vnAs+JeaBLunSrafYj0O6A$fIMcuoRTx2iCA9Z1MlciwS+RL/DGlGvcOEoCuwBcINM`. This is `$` delimited. the first position indicates the hashing algorithm used. See [this](https://github.com/github/github/blob/62505d2122ce3ba712677fa9d4f2b5a8ea2c6490/lib/github/password.rb#L58-L71) for more info on hashing. When authenticating by username/password, we need to look at the algorithm stored (`argon2id` in this example) apply the applicable algorithm or combination of algorithms (some of these are hashes of hashes as we proactively upgraded the hash to the value stored in place in the db).
- `weak_password_check_result`: This varbinary column stores data about whether the user’s passwrod has been known compromised or is weak. It contains other metadata (example: the date the password was determined weak). In the example of weak password, users have a time limit on when to change their password before we lock them out. Note, we may need to write a custom parser to deserialize this when we read it from the db for username/password authentication because may be ruby-specific serialization.
- `token_secret`: This column is not needed for our immediate needs for authnd authentication methods. However, this is used to sign things for the user that aren’t persisted in the db. We are storing it in authnd as we will eventually need to support this.
- `suspended_at`: Used to determine if the user is currently suspended.
- `disabled`: Users can be disabled if they are over their plan limit. It is our understanding that this may only apply to organizations, however, which are stored in the users table. So this may not apply to authnd. This column could potentially be scrapped. We opted to include it in the authnd users schema for now as it will be easier to remove columns than add them later.

# Example Data
The following section was adapted from our feature spikes to give good examples on how data relates in our schema for different types of credentials.

## User-to-Server Tokens
There are 3 types of user-to-server oauth access tokens. Here's how you distinguish between them in `oauth_accesses`:
- PAT: `application_type = OauthApplication`, `application_id = 0`
- OAuth Application: `application_type = OauthApplication`, `application_id > 0`
- GitHub Application: `application_type = Integration`, `application_id > 0`

### Special note on Access Tokens vs OAuth Accesses
A PAT is a user-to-server OAuth Access that is created by the user and can be used in requests to act on behalf of that user. An OAuth Application is authenticated by a user/org and is then issued a user-to-server OAuth access to act on behalf of the user/org. You can also be issued the user-to-server OAuth Access for a GitHub App the same way as an OAuth Application, but GH Apps also introduce a whole different concept of an `Access Token`.

An `Access Token` is a server-to-server token that is generated by a GH App and is to be used by another service that it integrates with. That service then acts as the GH App. We will cover more on that in the next section on "Server-to-Server Tokens"

The following examples show the relevant tables for each token type and example data for each.

For all scenarios, the token scopes are encoded from `oauth_accesses.raw_data`, rather than using the the `scopes` column from `oauth_authorizations`. The two values are normally the same but for some tokens they seem to be different.

### PAT

_oauth_accesses_
| id | user\_id | application\_id | created\_at | updated\_at | accessed\_at | hashed\_token | token\_last\_eight | fingerprint | authorization\_id | application\_type | expires\_at\_timestamp |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | 2 | 0 | 2021-01-14 16:50:01 | 2021-01-14 16:50:01 | NULL | NnDql+y5QiW1k4anYxOI3xnSgWUAQeI9aA0oLzfrmJ0= | 1d54cef3 | NULL | 1 | OauthApplication | NULL |

### OAuth Application
_oauth_accesses_
| id | user\_id | application\_id | created\_at | updated\_at | accessed\_at | hashed\_token | token\_last\_eight | fingerprint | authorization\_id | application\_type | expires\_at\_timestamp |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 2 | 2 | 2 | 2021-01-25 16:28:49 | 2021-01-25 16:28:49 | 2021-01-25 16:28:50 | 8DtdMNl0u0fJt72itWugINC0sGHGwjX44MJsF29zDFk= | 7361ab5a | NULL | 2 | OauthApplication | NULL |


_oauth_applications_
| id | name | user\_id | created\_at | updated\_at | state |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 2 | oauth-app-test | 2 | 2021-01-25 16:27:15 | 2021-01-25 16:27:15 | 0 |

### GitHub App
_oauth_accesses_
| id | user\_id | application\_id | created\_at | updated\_at | accessed\_at | hashed\_token | token\_last\_eight | fingerprint | authorization\_id | application\_type | expires\_at\_timestamp |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 3 | 2 | 1 | 2021-01-25 16:39:40 | 2021-01-25 16:39:41 | 2021-01-25 16:39:41 | tS9h7263S7FY76xPx5hMaGIhHbGfNaVnoO/wyWSt+Wk= | 2e4b4175 | NULL | 3 | Integration | 1611650381 |


## Server-to-Server Tokens
TBD