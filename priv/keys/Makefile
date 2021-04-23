.PHONY: all

key.pem cert.pem:
	openssl req -x509 -sha256 -nodes -newkey rsa:4096 -config cert.cnf \
		-keyout key.pem -days 99999 -out cert.pem

all: key.pem cert.pem
