package schemas

const (
	Mysql1RO string = "mysql1:ro"
	AuthndRO string = "authnd:ro"
	AuthndRW string = "authnd:rw"
	CollabRO string = "collab:ro"
	CollabRW string = "collab:rw"
	LodgeRO  string = "lodge:ro"
	LodgeRW  string = "lodge:rw"
)

func All() []string {
	return []string{
		Mysql1RO,
		AuthndRO,
		AuthndRW,
		CollabRO,
		CollabRW,
		LodgeRO,
		LodgeRW,
	}
}
