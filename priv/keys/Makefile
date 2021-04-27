all: key.pem cert.pem dh.pem dkim.pem dkim-private.pem

key.pem cert.pem:
	openssl req -x509 -sha256 -nodes -newkey rsa:4096 -config cert.cnf \
		-keyout key.pem -days 99999 -out cert.pem

dkim.pem dkim-private.pem:
	openssl genrsa -out dkim-private.pem 2048
	openssl rsa -in dkim-private.pem -pubout -out dkim.pem

dh.pem:
	openssl dhparam -out $@ 4096

.PHONY: all
