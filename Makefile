index:
	pandoc -s --toc index.md -o index.html --template=template3.html

doc:
	doc2 -i -p .

all: index doc
