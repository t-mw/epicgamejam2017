all:
	moonc -t build .
	cp -r lib build
watch:
	moonc -w -t build .

