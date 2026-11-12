package api

import "github.com/twitchtv/twirp"

func NewSomethingSomthing() error {
	return twirp.RequiredArgumentError("selector")
}
