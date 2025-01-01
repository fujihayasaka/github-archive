package schedules

import (
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

const scheduleLockName = "schedule_repo"

func (r *dbStore) StartTests() error {
	return testutils.StartTests(r.rawDB, scheduleLockName)
}

func (r *dbStore) EndTests() error {
	return testutils.EndTests(r.rawDB, scheduleLockName)
}

func (r *dbStore) EmptyForTests() error {
	_, err := r.rawDB.Exec(`TRUNCATE workflow_schedules`)
	return err
}

func (r *dbStore) CountForTests(repoID types.GlobalID) (int, error) {
	row := r.rawDB.QueryRow(`select count(*) as count from workflow_schedules
		where repository_node_id = ?`, repoID)
	count := 0
	err := row.Scan(&count)
	return count, err
}

func (r *dbStore) CountForTestsNextColumn(repoID types.GlobalID) (int, error) {
	row := r.rawDB.QueryRow(`select count(*) as count from workflow_schedules
		where repository_next_id = ?`, repoID)
	count := 0
	err := row.Scan(&count)
	return count, err
}

func (r *dbStore) CountForFileForTests(repoID types.GlobalID, path string) (int, error) {
	row := r.rawDB.QueryRow(`select count(*) as count from workflow_schedules
		where repository_node_id = ?
			and workflow_file_path = ?`, repoID, path)
	count := 0
	err := row.Scan(&count)
	return count, err
}

func (r *dbStore) CountForFileForTestsNextColumn(repoID types.GlobalID, path string) (int, error) {
	row := r.rawDB.QueryRow(`select count(*) as count from workflow_schedules
		where repository_next_id = ?
			and workflow_file_path = ?`, repoID, path)
	count := 0
	err := row.Scan(&count)
	return count, err
}
