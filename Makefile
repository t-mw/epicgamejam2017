all:
	moonc -t build .
	cp -r lib build
	cp -r music build
watch:
	moonc -w -t build .

