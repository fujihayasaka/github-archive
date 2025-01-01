package ctes

import "github.com/simon-engledew/sqlh"

func With(query sqlh.Expr, ctes []sqlh.Expr) sqlh.Expr {
	return SQL("WITH ? ?", sqlh.In(ctes), query)
}
