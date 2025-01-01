# \[Proposal] Improving our SQL query building

## Introduction

In this proposal we are going to see how the database access layer is currently done in our codebase, what are the problems with it, and how we can improve it.

There are way too many SQL libraries out there, with different degree of features depending on what you are more comfortable with.
To keep things as simple as possible, I have only studied these libraries in the category of SQL builders, that is, libraries that help building SQL queries and nothing more:

- [Squirrel][squirrel]: A fluent SQL query builder
- [SQL Builder][go-sqlbuilder]: A flexible and powerful SQL string builder library plus a zero-config ORM

While studying these libraries, I have tried to focus on the following principles:

- How easy are they to set up?
- How easy is to use them in our current codebase? Do we need to make many changes/refactors to use them?

I have also opened a PR for each library to try to showcase the integration process on our existing `subscriptions/storage` package:

- [Squirrel][pr-squirrel]
- [SQL Builder][pr-sqlbuilder]

## The Problem

The implementation of our current Database Access Layer is ad hoc. We add the database structures (tables) and then build structs that mirror those structures. After that we write the SQL queries we need and all the code around how we interact with these queries, that is, calling the DB driver, parsing results, handling errors, etc. In some cases the SQL queries are complex and we end up with string interpolation of arguments to build them. This can be a security vulnerability due to SQL injection if we are not careful.

Note that this is not a bad approach to interact with the DB (except for the string interpolation), and it's pretty common in Go applications.

Right now we spend time:

- Defining complex SQL queries and building them through string interpolation
- Each package has a different way to build these queries

All of these translates to extra time invested on SQL query management.

## Requirements of a SQL integration library

Given the problems highlighted, we can try to define what are the requirements for a good SQL library that can help us to improve how we write SQL queries:

- Small surface area: A complex and bloated solution can give us a lot of features, but that doesn't mean we need them. If we use tools that have a small surface area we can still have control over our Database access. This will also help use to migrate to the new solution without changing too many parts of our codebase
- SQL query building: Writing plain SQL in strings is ok for small or common queries. It gets complicated due SQL natural structure, once queries get more complex. A good SQL query builder can help us to manage all kind of SQL queries and prevent security issues at the same time

## The Proposal: Squirrel

[Squirrel][squirrel] is a library mentioned in GitHub's [Database Access and Go][gh-db-go] document and it's also mentioned in our [#gophers][slack-gophers] Slack channel. It is also well regarded in the Go community and often recommended.

It has a small surface area and its basic types are composable thanks to its `Sqlizer` interface. This also means that we could extend it if we needed more complex expressions.

An example on how to use it to build the complex SQL query we use to [fetch matching subscriptions][subscriptions-matching-query]:

```go
func buildMatchingSubscriptionsQuery(routingKey string, topics []datastructures.Topic, subject string, trigger string, subAttributes ...datastructures.Attribute) (string, []interface{}, error) {
	topicsFilter := squirrel.Or{}
	for _, topic := range topics {
		condition := squirrel.And{
			squirrel.Eq{"subscriptions_v2.topic_type": topic.Type},
			squirrel.Eq{"subscriptions_v2.topic_value": topic.Value},
		}
		topicsFilter = append(topicsFilter, condition)
	}

	anySubject := squirrel.Expr("subscriptions_v2.subject_type = 'any'")
	anyTrigger := squirrel.Expr("subscriptions_v2.trigger = 'any'")
	subjectAndTriggerFilter := squirrel.Or{
		squirrel.And{anySubject, anyTrigger},
		squirrel.And{squirrel.Eq{"subscriptions_v2.subject_type": subject}, anyTrigger},
		squirrel.And{squirrel.Eq{"subscriptions_v2.subject_type": subject}, squirrel.Eq{"subscriptions_v2.trigger": trigger}},
	}

	matchRulesFilter := squirrel.Or{squirrel.Eq{"subscription_match_rules.subscription_id": nil}}
	for _, rule := range subAttributes {
		expr := squirrel.And{
			squirrel.Eq{"subscription_match_rules.attribute": rule.Name},
			squirrel.Or{
				squirrel.Eq{"subscription_match_rules.value": rule.Value},
				squirrel.Expr("subscription_match_rules.match != 'eq'"),
			},
		}

		matchRulesFilter = append(matchRulesFilter, expr)
	}

	subquery := squirrel.Select("subscriptions_v2.id", "user_id", "reason").
		From("subscriptions_v2").
		LeftJoin("subscription_match_rules ON subscriptions_v2.id = subscription_match_rules.subscription_id").
		Where(topicsFilter).
		Where(subjectAndTriggerFilter).
		Where(matchRulesFilter)

	query := squirrel.Select(
		"pre_selected_subscriptions.id AS ref_id",
		"pre_selected_subscriptions.user_id",
		"pre_selected_subscriptions.reason",
		"subscription_match_rules.attribute",
		"subscription_match_rules.value",
		"subscription_match_rules.`match` AS match_rule",
	).
		FromSelect(subquery, "pre_selected_subscriptions").
		LeftJoin("subscription_match_rules ON pre_selected_subscriptions.id = subscription_match_rules.subscription_id")

	return query.ToSql()
}
```

We can see that the query is still complex, but the steps to build it are more clear since it's based on basic structs. This means no chasing down query arguments or different parts of the interpolated SQL string.

The library still allows us to use SQL when needed (like with `AS` aliases), although it's possible to declare those with `squirrel.Alias`, for example.

Another advantage of Squirrel is that we can extend it with expressions. For example, to add a custom expression that represents `col IS NULL`, we could do the following:

```go
type isNullExpr struct {
	column string
}

// squirrel.Sqlizer interface
func (expr isNullExpr) ToSql() (string, []interface{}, error) {
	return squirrel.Eq{expr.column: nil}.ToSql()
}

// Example:
//   builder := squirrel.Select("*").From("table").Where(isNull("ref_id"))
func isNull(column string) isNullExpr {
	return isNullExpr{column}
}
```

Squirrel is also used in [other projects across GitHub][cs-squirrel].

### Cons

Probably the biggest disadvantage of Squirrel is that is in maintenance mode, that is, no more features and a slow pace to fix bugs. In the other hand is a very stable lib with a small surface area.


## Another option: Go SQL Builder

[Go SQL Builder][go-sqlbuilder] works in a very similar way as Squirrel, that is, it offers a fluent API to build SQL statements. It also has a small ORM integrated that can be used with special tags in our structs.

An example on how to use it to build the complex SQL query we use to [fetch matching subscriptions][subscriptions-matching-query]:

```go
func buildMatchingSubscriptionsQuery(routingKey string, topics []datastructures.Topic, subject string, trigger string, subAttributes ...datastructures.Attribute) (string, []interface{}) {
	subquery := sqlbuilder.NewSelectBuilder()
	subquery.
		Select("subscriptions_v2.id", "user_id", "reason").
		From("subscriptions_v2").
		JoinWithOption(
			sqlbuilder.LeftJoin,
			"subscription_match_rules",
			"subscriptions_v2.id = subscription_match_rules.subscription_id",
		).

	var topicsFilter []string
	for _, topic := range topics {
		condition := subquery.And(
			subquery.Equal("subscriptions_v2.topic_type", topic.Type),
			subquery.Equal("subscriptions_v2.topic_value", topic.Value),
		)
		topicsFilter = append(topicsFilter, condition)
	}
	subquery.Where(subquery.Or(topicsFilter...))

	subquery.Where(subquery.Or(
		subquery.And("subscriptions_v2.subject_type = 'any'", "subscriptions_v2.trigger = 'any'"),
		subquery.And(subquery.Equal("subscriptions_v2.subject_type", subject), "subscriptions_v2.trigger = 'any'"),
		subquery.And(subquery.Equal("subscriptions_v2.subject_type", subject), subquery.Equal("subscriptions_v2.trigger", trigger)),
	))

	matchRulesFilter := []string{subquery.IsNull("subscription_match_rules.subscription_id")}
	for _, rule := range subAttributes {
		condition := subquery.And(
			subquery.Equal("subscription_match_rules.attribute", rule.Name),
			subquery.Or(
				subquery.Equal("subscription_match_rules.value", rule.Value),
				"subscription_match_rules.match != 'eq'",
			),
		)
		matchRulesFilter = append(matchRulesFilter, condition)
	}
	subquery.Where(subquery.Or(matchRulesFilter...))

	query := sqlbuilder.NewSelectBuilder()
	query.
		Select(
			query.As("pre_selected_subscriptions.id", "ref_id"),
			"pre_selected_subscriptions.user_id",
			"pre_selected_subscriptions.reason",
			"subscription_match_rules.attribute",
			"subscription_match_rules.value",
			query.As("subscription_match_rules.`match`", "match_rule"),
		).
		From(query.BuilderAs(subquery, "pre_selected_subscriptions")).
		JoinWithOption(
			sqlbuilder.LeftJoin,
			"subscription_match_rules",
			"pre_selected_subscriptions.id = subscription_match_rules.subscription_id",
		)

	return query.Build()
}
```

As we can see, the building process is very similar to Squirrel. The main difference is that to build expressions (like `OR` statements, etc) we have to use the same builder. This is because internally the builder keeps track of the possible arguments needed for the SQL at the end. This detail might limit how we can extend it, if we need it at all.

Apart of the fact that SQL builders are being mutated all the time, I couldn't find much more differences with Squirrel.

Since this library also offers a small ORM that I don't think we need (not in the near term at least), we can say that it has a bigger surface area.

### Cons

Go SQL Builder doesn't seem as used as Squirrel, and it's not used at GitHub (at least I couldn't find other projects using it). In the other hand it is actively maintained, which is always a good thing.

## Libraries left behind

Other libraries that I didn't have time to check or were discarded already:

- [Ent][ent]: This full ORM was explored in the past. It is quite complex to use in our already big codebase, so we decided to not use it.
- [sqlc][]: This is a code generator. We tried to use it but it wasn't playing nice with our package structures. It also doesn't work well with complex dynamic queries.
- [GORM][]: This is probably one of the most famous ORM libraries for Go out there, but our own internal document doesn't recommend it. I decided to focus on libraries with smaller surfaces for the moment.
- [SQLBoiler][]: Another ORM with some traction. It is also recommended in our main document. However it has some caveats around foreign keys for relations and getting around those seems cumbersome. I wanted to check libraries that work for us, not the other way around.


[squirrel]: https://github.com/Masterminds/squirrel
[go-sqlbuilder]: https://github.com/huandu/go-sqlbuilder
[pr-squirrel]: https://github.com/github/notifyd/pull/1334
[pr-sqlbuilder]: https://github.com/github/notifyd/pull/1333
[subscriptions-matching-query]: https://github.com/github/notifyd/blob/221e1eccbe12d2191ed78e1da359fcdd29ce72b0/internal/pkg/subscriptions/storage.go#L137-L193
[gh-db-go]: https://github.com/github/go/blob/main/docs/database_access.md
[ent]: https://entgo.io/
[sqlc]: https://sqlc.dev/
[cs-squirrel]: https://cs.github.com/?scopeName=All+repos&scope=&q=org%3Agithub+%22Masterminds%2Fsquirrel%22+path%3Ago.mod
[GORM]: https://gorm.io/
[SQLBoiler]: https://github.com/volatiletech/sqlboiler
[slack-gophers]: https://github.slack.com/archives/C0MQYTAG1/p1649150571263779
