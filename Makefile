index:
	pandoc -s --toc index.md -o index.html --template=template3.html --metadata pagetitle='embedr: D and R interoperability'
	cp index.html site/

doc:
	doc2 -i -p .

all: index doc

other:
	pandoc -s dmd-vs-compilefile.md -o dmd-vs-compilefile.html --template=template3.html
	pandoc -s r-not-dub.md -o r-not-dub.html --template=template3.html
	pandoc -s ldc.md -o ldc.html --template=template3.html
	pandoc -s pulling-r-data.md -o pulling-r-data.html --template=template3.html
