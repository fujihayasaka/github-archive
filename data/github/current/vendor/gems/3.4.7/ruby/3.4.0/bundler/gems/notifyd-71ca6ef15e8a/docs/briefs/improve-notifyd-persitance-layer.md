# Improve Notifyd Golang database layer

## Problem statement

Most of current database layer code is quite tedious in support since we have to use low-level MySQL `sql` go package. Examples [one](https://github.com/github/notifyd/blob/e001b38193cfd4da3b4c38bf8171d04a47d470b0/internal/mobile/devicetokens/devicetokens.go#L59-L85) [two](https://github.com/github/notifyd/blob/e001b38193cfd4da3b4c38bf8171d04a47d470b0/internal/mobile/devicetokens/devicetokens.go#L117-L138) 
From developmer productivity perspecive we want to have better tools to work with data persistance layer in Golang service. 

Another problem that exists with current approach that our queries are not statically typed - which creates some space for logical mistakes. 

## Context
We are going to use DB related features significantly more often once we start thinking about the `subscription service` in the context of `notifyd` email support initiative. 
That's why we need better tools to write and maintain SQL queries. 

Talking to the team we felt complexity working with the current solution across many discussions, especially coming from an `ActiveRecord` background.

## Goals and objectives
- Investigate available solutions in Go ecosystem
- Spike into integrating Go ORM/SQL libraries
- Provide convinient tools for broader team to work with DB layer 
   -  Transactions
   -  Writing DB queries and parsing results
   -  Connections management

## Assumptions
None

## Guiding Principles
* Notifyd should be able to switch ORM/SQL solution if it will be neccesary.
