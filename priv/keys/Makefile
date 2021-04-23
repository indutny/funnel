all: key.pem cert.pem dh.pem

key.pem cert.pem:
	openssl req -x509 -sha256 -nodes -newkey rsa:4096 -config cert.cnf \
		-keyout key.pem -days 99999 -out cert.pem

dh.pem:
	openssl dhparam -out $@ 4096

.PHONY: all
