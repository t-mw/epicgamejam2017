all:
	moonc -t build .
	cp -r lib build
	cp -r music build
	cp -r graphics build
watch:
	moonc -w -t build .

