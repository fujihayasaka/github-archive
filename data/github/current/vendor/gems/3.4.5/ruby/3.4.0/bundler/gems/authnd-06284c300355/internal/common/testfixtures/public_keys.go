package testfixtures

import (
	"encoding/base64"

	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/ssh"
	"github.com/pkg/errors"
	"gopkg.in/guregu/null.v4"
)

var PublicKeys = []*models.PublicKey{
	MonalisaPublicKey,
	MonalisaUnverifiedPublicKey,
	MonalisaUnsupportedAlgoPublicKey,
	TrollPublicKey,
	UnknownUserPublicKey,
	DeployPublicKey,
	MismatchPublicKey,
	MonalisaOutdatedPublicKey,
	DupeTestKey,
}

const (
	monalisaUnverifiedKey    = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDU4E3R8GF2BM78lE0y5Ec9ty0Rs5ZRu//b4FpjwoWD8e4Rh+f3tVIZys0j+WRAe7v5A0ob7dFBjfGkUxZaP+ZSaPBsIveUo3uNgjZ2gdxTnDjqz0X3uq55ZiB80x3soLfKjdPw+/dtn9eOeMCEp71FU7zAf0IgdDzW79zcXzMddQR3teseFe0aQuy+IDPD7yO/wvsQ1Kq6cIhCg5o1zto1lF5KqpP9Z15tCL7AxS/qhidWis3kYjCMV++cvbv6IZR7Z4SDH04SOgHbGg18hSukQ0JPYJ4c/WytfWZkGULqnWeHwW853gmpfzv/jbYuC8QSnKPvsEk+hEtnM3MVLGgqH9RXZxckq5wlSMzsRrxen5qoi5t5GWNJYZTN9YiXW392lbKfPyCT40Op/l0VnkDbSlW3rVs+r8A/X8rajM1hlgeNSyeyHQtKolW21MNBoaiqk/ORn/ydLPOkfdFo9FLdHrZUroF9zXa8aXfT82TSR2RRjnM+5QOMqUDdKLPBv50=`
	monalisaAuthorizedKey    = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCbRAVjnmw5FEEO9pSMzgybaeMFAtvjFDFvLChgUioB2AdIBTW6M/NKW7QSlr2AJec7KdFVNAibABvWAWpyGW23XgRKmESt5RFYy5sWKybEO479aucm2RoO1IaClvsU6mbJSrEZVn+M3hqtOkdhcsugQPMOVzP4PXIN86xWd37tWPGkfBg3YwnL97LKoIa2/awHJdKjY0rvyPTqju9DPZm7smLHsUGPndOrWw+ntumPaq4OLpDOxQamMNVIKyPuxXHoflGkyPJaZEPUrT/VVYGtY7uD6nq6iR43c7+xw6nRsQ3IvNeKHdvYGZzYnmwINpo199N+huLc5Cglj29jiIZrwJsyZl0ABh1MnA0ENPChl4Kp9XA4k6g7cf4TRRW1W7iXfqKKxGRy86VXJp8oHfARQARn8yvIVuVIY/zoT3ZcM9ts/M2VrWeVlrB35wSdF8LdOLa68mKQI5sSHkLcuLn/4KtwrjcJJWRfNSABDO2v+dn9HmC4jm0WTyRQFWTypfM=`
	trollAuthorizedKey       = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9gUCxHR/eOV2UYIiM24TDdqQ5TH9vh4/LTvuFPeRL0DDj+1O4q06WxYgMj4K56YaVFZ6oAVVoaPUDCwbYx/0h3EO48kXZDp/m/cuucSIda/h79OxLzqZxBpKQwEFirRK2TxVWnhYuc3bfrovEvxBYh26HicuNs6LYwjF96VsGtK2wwaKe6jGrNw7ZFlN/iks5Aq67upqr4YdERbCSXRtwsKuuFV/dovhODXnvnLIxPPjmtoWltizgFwE2ufwoxcVKFZhDRqf/UBRa/scjTPDIr39x0ZLLQe6jgO8aeogxC0f3BT2ntkIIuh57A6xUTqifpxWweT3xYstcR2mxR1EUQ8QkWz2JYFjcjgGdEU2VN1YMeuUhLhz3OpESiY/nmySOqskipol4Ss6ejco0rdKvckRWZvfzUE9X5NnnMP6DsuUAGR5mdw0bTvKIvw4is0+JQ0DrEB6qE0PwcYrlLVvM9cVj8BHKdIGloYUuxZ4jGzaZ5XWjXj/VQTsdUQca0Us=`
	unknownUserAuthorizedKey = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDM3DZNXNf+jlrVHKbwX77vqlwNW5ZWVtf06Iuzdhhds1ehsE5u30Z+onI8MN7RTUYKEjk9k1qTZG3dxXiSYcdfOYZVCvhSCC/QukcoTUXH1vhrHSpkgGcVUZjkMWFn5lXp+0ZTYEL8O+bYHz/jFRm4j080pBogOmaX3TxvX1R9aehyB+3X6Iy9m0NOq5lghHf0s+TZH2yFbAboRuL29kOPs1luxxscVIVUGKH2zE/nTpNUOgrKZapQdxL/rcd7mQr40zGdTx9uZFqWAe2YVmCkBdT3SwsQiL73o4AmEw+8feJQLM5FLKKZuqc8wXViSzFh+Gdu0k2/JfU0hS1vNr6GVwzmXGXfS5LzxKxFHkw600tqvk1pJ4Mnnd6RuTcsQ7MDoHQzFWJaEWdz0Fq3Un2ctHNWCNuNKyuop2Z8gT9bIf/hZBCQQPeOAqLwF5/uhuw0w054pA7dKrMHyT5kHtDM6LyYZ5PKpuLOVTJVt6tS1Iz/buq6vmFkHnBqan+kMKU=`
	deployAuthorizedKey      = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDpB3KJGRZduzohnMCQga+R/PbOXa7sN8hizp0lbMwkfCga3FzPDWImeGTPYr7DtLDOxp72p1+5Pwce1SDIalu4oimZkJ9urVWN9QrOh20qwP5YG6D/s5uL7otq6hFdE2kYzpIsHxnFcZapCBMtyW7m0V9e5bx9QcGlOpwV4jUQ4rpGh+WyBR9DqKNW4lJUHJSTOawdnqcfD6oeuqYj1OmHFf90q+Mmx5pHWVl9LvaYmcqJipwcvSHcM4lpvuFvNeILoBd5rjfOumYKrTquwNwmLoq1R5L9M8O1la+mkU9DQOVyNqniL7ahIUICW/7tN7rxvzE5S5RoQ5hLvKBXckK2W+kqaZ5+dlxxdHJ4+7fY826tUIn1RUiVXCGFrWw7BZfAdSAb6culnXlpb3F1bq+FcGacuQ1XVLN060BERSfkyAnYk+3XsoGpEk46gfg5yLsvL0uX+DzDYWqY3OMBhGlb/VyHsd96cAB8WS7PISZ30CfomdUza4sZ7yhdE06WDbs=`
	MismatchSuppliedKeyRaw   = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC4R7k99R/QlwsCVbV2rnVjz8dleoHZp/tT7QCnXoV6oicdfPE7TTKAAKgPYcyDBb3R4vijXrmwC1yjZdTtgSylGAoTrHY+A6QLAL273wCQpbYjz3Xq0e3u48OEypIqajkp7XpI1NEBUHE8PkyHV4TvBmflNCwK6TRKyrxcl5FLSUdhlO089lHrfBCkyqIvlyyjTqU9DK1WS/GimHRzRx6cqKHHBx6F2a1d7/xCSqxyAKekG9zXk5F0jwiQC5ylnkp31aljU+7MkQrh6dK6KSC/ulFvFbw9JkWkdFgcUvBpjLJXR5dXfN+G+g7x7wyi9thB2SpQXZ+gPEOLePM93FwrB+Vr3rtLSJ2zTPcXXewbM2fVd5BpypVLakYlWdUG3ii3d5xxx0eFLzoH/6M2uC3SSTchLRe8Q1drekhru6ov1hjtxVkqN8lYTlODgJTuFE45tTf3HzJosuOzDlRThmNRZztRcGwSF4pMEv2zSxrWkcg303IcqBAIk+zLnI1H6IE=`
	mismatchStoredKey        = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCqQl18VHTh+2fgBqUrrO94xT8W1eESN+OpgRm9WaTt1rIm8lGidiCChHSnvchyZpNtQfn7sa4UHH0SKbvAe0z3RkKWrGqCBulYYscKjR09wccP0Xl3F0vrNZW752ddybZMbT1Z+hT63p3AxfzNNwZ+1RdkL+yY9jxLlgXuXXtrNEIC8SPK7fbPbzkZIKbYgIkWS1UFNMRYHagoQKyIJXIA7k1oGVbEd0KMGABOlt5y7QtPXtpIRU+MdaN1oiUTcyVP4CttaYIf4+uCV3TyFHNMJFaqfVOVvkO/nxPE7KJVpVzU96KV/dI1u56NOffgudp33gYdj7f3APXAA21A99QlFYYZNrlCw8ZQzZYOdtUZbq+LW614Opev3ZqJFUqdOlP36oShTB3V/UX3OjYYCQb1lPSwRBwgecfnLrK5Prp8KALHqLhqJKHGL7WahLgY8rEdGPaF6ZMoyPdOxQzbVAB1TuLKMwOaSy6KKwR6FvzRZt15lM9pMNSAAG/ehIM4LfE=`
	// from https://sourcegraph.com/github.com/golang/crypto/-/commit/86a70503ff7e82ffc18c7b0de83db35da4791e6a
	monalisaUnsupportedAlgoKey = `something-random AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBGRNqlFgED/pf4zXz8IzqA6CALNwYcwgd4MQDmIS1GOtn1SySFObiuyJaOlpqkV5FeEifhxfIC2ejKKtNyO4CysAAAAEc3NoOg==`
	// See issue 250 for background
	// generated with:
	// % /usr/local/Cellar/putty/0.74/bin/puttygen -t dsa -b 2047 -o /tmp/t
	// /usr/local/Cellar/putty/0.74/bin/puttygen /tmp/t -O public-openssh -o /tmp/t.pub
	dsa2047BitKey = `ssh-dss AAAAB3NzaC1kc3MAAAEAUk4aHkStTTdgW7TSsl/FSb6UXLn4aoGF6zopc2s+k/foT22FMHCC7CvGZcQRzikZyG08rQtQMkHTixORA6ZPLvpSMuyrFw9g+W0DZkgqVlPNgL7IPrrz1Y+4cnrurYXZL1Ci0OTVvbrH6kWAZi1OnXxW/qvNFdS/1vZHYMNIHvc/OTG2eWziIf4/hOSIYtJqsH/L/LFbRSxXALBTSBKbhxN56weLSYMTEf4S38vTKPE9M8pI8SkCg1oLdaN/HP5gU1NUjFcY7uclVieiK/E0RkSdWV8tHHKIvTGGXGFvX5W+nvk5AvjYKHARGmEZm5SZSOJDkNPezsIoorFT41nrKwAAABUArThaNnuFvMLMODqBJsy+Aj5H+48AAAEAO9BzUI4fvFOw3X5j6flrKRiLjNaNOvM7XPr+L9WTtnvO2QCp5rVS/kAMaQFYDkSRFTHhi5CaSFZ5I0QnsGCE1tonyesjrgL1FN/Tx7YUI/EyhjI1TDbzHbzSH0nL6TSF14XIXSXqcCC7EZXIJitzQp484UT8GRbeLeC42uWQo+iHWpsGq6SgC/Vr52nSbsWsQe6nuKAj9671K8vxFLNXWU5rZ9+2t9X6yAuBrPKzX2oqEqdHXiclJzx5yN3E0BX+j3detFZWh8VngKLELWl6Aq+KuhKqVM6VK41LyC4iBZKiBOKB+8oKfni9Z7ctc7ZYflmdm28tfWveUuC90exviAAAAQAbE5fVI3gPd+BRZC2HKbvouP/azHUoKnnN1GMHaj0dtXEOTuUrA5gqPkz4H2SMN41fHdmY0Q/L+uVApgD6gPUr5YCszrbjdRS3KmGjojWcrMU+J9wGXtwZwTOpAJmdpb0tNVrK12NT6KY6my0wDrtKbKPRGI5ttAqY4VZ1R/qG8dfjxvSywzdnnRMjcrdZWemYXb9KY8RTu5facfhrS/rMaQQilYoPeTQQgrtRSCJVr/ckVGECtnKBrcuZ1TtKVelak146AHK3hpCSmmXgpQam+Yc0IafWHQVlfgfhxIQPaA9HXF+17RpoE0iuRL9c2HCJORoIKGSinK/KsBg9aOrN`
	dupeTestKey   = `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCoyb57CWkYhDwdaH263WexSZhAp0vxteMLTGa5tvsTrZsD/t7151ygcYH9Xyd/jRvo15M17kUqCOnkNi2Ju2npsG8RpL5Fim2jEU8bLcP4TEk/UdMYi2qS1xtLOPvNvkepOOWOaRVmf4bBHPfMyqm5URWdmKYd1DKmgxTMxnuL2mQkN3CRK+VR2h+bTiLSFeQZo5ZG6mBPCDknXyH+lyWBtN0iEEpdHBLAfcFbJIqWB4KmQrjcahn2UbWRO2xsG/QHNZzBpF/+QTobE43smx9MXl/aiH8+swlTOsPbt5xIc3//uaz3ZaPgEMRr9WE3y9095Glnt2YhOa+uD7+z8MvlIU5KC/MNQZNtM2rqYMVVGQRsMag6XQ+bmFrhdiGv/7YgybHfB63wHb1BeDAIqo/X/oB57BjMDdJ5VyV9IZmaS2c+fDu20ARL82L5Yzu5GKEKOPFwSFn5hqZhOURmbZcgVMtAQ9cfZcoEZyGvnz6txiw262U97Sb/6zB2INIw+3U=`
)

var MonalisaPublicKey = &models.PublicKey{
	ID:                1,
	Key:               monalisaAuthorizedKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	UserID:            null.IntFrom(MonalisaUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(monalisaAuthorizedKey),
}

var MonalisaUnverifiedPublicKey = &models.PublicKey{
	ID:                2,
	Key:               monalisaUnverifiedKey,
	UserID:            null.IntFrom(MonalisaUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(monalisaUnverifiedKey),
}

var MonalisaUnsupportedAlgoPublicKey = &models.PublicKey{
	ID:                3,
	Key:               monalisaUnsupportedAlgoKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	UserID:            null.IntFrom(MonalisaUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(monalisaUnsupportedAlgoKey),
}

var TrollPublicKey = &models.PublicKey{
	ID:                4,
	Key:               trollAuthorizedKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	UserID:            null.IntFrom(TrollUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(trollAuthorizedKey),
}

// this key belongs to an unknown user 4.
var UnknownUserPublicKey = &models.PublicKey{
	ID:                5,
	Key:               unknownUserAuthorizedKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	RepositoryID:      null.IntFrom(4),
	FingerprintSHA256: mustGenerateSHA256RawBytes(unknownUserAuthorizedKey),
}

var DeployPublicKey = &models.PublicKey{
	ID:                7,
	Key:               deployAuthorizedKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	RepositoryID:      null.IntFrom(1),
	FingerprintSHA256: mustGenerateSHA256RawBytes(deployAuthorizedKey),
}

// key does not match the supplied key stored in fingerprint
var MismatchPublicKey = &models.PublicKey{
	ID:                8,
	Key:               mismatchStoredKey,
	UserID:            null.IntFrom(MismatchPublicKeyUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(MismatchSuppliedKeyRaw),
}

var MonalisaOutdatedPublicKey = &models.PublicKey{
	ID:                9,
	Key:               dsa2047BitKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	UserID:            null.IntFrom(MonalisaUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(dsa2047BitKey),
}

var DupeTestKey = &models.PublicKey{
	ID:                21,
	Key:               dupeTestKey,
	VerifiedAt:        OneHundredHoursAgoNullMysqlDateTime,
	UserID:            null.IntFrom(MonalisaUser.ID),
	FingerprintSHA256: mustGenerateSHA256RawBytes(dupeTestKey),
}

func mustGenerateSHA256RawBytes(publicKey string) []byte {
	fingerprint := ssh.MustGenerateSHA256(publicKey)
	dat, err := base64.RawStdEncoding.DecodeString(fingerprint)
	if err != nil {
		panic(errors.Wrap(err, "failed to decode fingerprint"))
	}
	return dat
}
