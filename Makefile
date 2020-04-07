.PHONY = site clean dev

site:
	bundle exec jekyll build

clean:
	bundle exec jekyll clean

dev:
	bundle exec jekyll serve