# Use EntGo library for IMS store layer

## Status
In review

***

## Context
Current store layer relies a lot on default `database/sql` standard library to interface with MySQL database. 

While it brings advantages of not having to depend on any external library, it also forces us to do lots of error-prone operations by hand, in multiple places.

![image](https://github.com/github/hosted-compute-ims/assets/5173831/6b0e187e-257f-4078-93c3-c729b84edf01)

Arguments to evaluate different options:
1) We have to define our SQL queries as plain strings, there is risk of creating malformed SQL query, there is no static type checks that would help us
2) We have to bind SQL query with data using positional arguments – it's easy to swap argument positions in a query and create a bug.
3) Once data is returned – we also need to manually map columns from each row to a given struct – it's another place which needs to be maintained and which could be a source of bugs.


## What alternatives do we have? 
In Golang ecosystem there are several alternatives that we could consider that were mentioned in [overview doc in Golang repo](https://github.com/github/go/blob/main/docs/database_access.md)
Also, we had brown bag session with team where we have discussed possible alternatives to interact with MySQL DB from a Golang application – [deck](https://docs.google.com/presentation/d/1dQe0j_ypVXvhgbk7aTaYUZ5BklQgT3_owNOcIgHim7I/edit#slide=id.g2a6d691cc7f_0_16)

### 1) Keep using database/sql 
We can keep using database/sql package as an option.

**Pros:**
- No library needed
- Very low level
- No additional work right now

**Cons:**
- Not type safe, queries are strings
- Verbose
- Easy to swap data positions in query
- We have to handle low level errors
- Hard to maintain in long run, lots of additional work in the long run
- We will end-up re-implementing ORM lib outselves

### 2) Use extension libraries (SQLx + Squirrel)
We can make use of extension libraries: 
- [SQLx](https://github.com/jmoiron/sqlx) - automatic unmarshal of Rows to Structs
- Generic SQL builder (let’s build SQL statement with Go instead of hardcoding a string) - for example [Squirrel](https://github.com/Masterminds/squirrel)

**Pros:**
- Less SQL hardcoded in strings
- No need to do Rows.Scan manually
- SQL is written by hand, lots of control for complex queries

**Cons:**
- Not typesafe store layer, we can still pass arguments to of wrong type to our queries
- We still have to handle lots of boilerplate code
- SQL is written by hand even for simpliest CRUD queries

### 3) Use code-generation library

We can use code-generation library that will generate SQL-like DSL that is specific to our own schema, for example [EntGo](https://entgo.io/docs/tutorial-setup).
Here is how it works:

<img width="754" alt="image" src="https://github.com/github/hosted-compute-ims/assets/5173831/bd273039-5003-4eea-bca6-30af3cd8d838">

Based on provided schema we would check-in to our codebase generated code that would provide typesafe layer for building SQL queries. 
With this approach we can achieve great balance between having typesafe and easy to use store layer and still keep control over SQL that we generate without relying on runtime reflection features.

**Pros:**
- Static typing based on code gen
- SQL-like DSL 
- Automatic struct mapping
- Easy code regeneration “go generate ./ent”
- We can fallback to RAW SQL queries if we even need it

**Cons:**
- Gen files in codebase
- Generator might not fit very obscure SQL cases, need to fallback to RAW query

Reference implementation is showcased in this [spike PR](https://github.com/github/hosted-compute-ims/pull/287)

### 4) Use full-featured ORM
As more extreme alternative we can use full-featured ORM, for example [GORM](https://gorm.io/index.html)

<img width="768" alt="image" src="https://github.com/github/hosted-compute-ims/assets/5173831/90efa56b-4a03-4b8c-a238-e6e7082523f0">

Somehow lots of folks at GitHub have discouraged us from using it, we should take it as a signal in our decision.


**Pros:**
- Mature ORM project
- Magic that just works (until doesn’t :trollface:)
- No/little SQL written

**Cons:**
- Perf issues in the past
- Runtime query building
- We would have to work with ORM specific DSL instead of SQL
- Hard to understand internals of GORM

## Decision

Per this ADR we have decided to go with option **3) Use code-generation library**  as it provides good balance between having enough control over SQL that is being generated on one side
and on another side it helps us to remove lots of boilerplate code when working with store layer.

