# Store pages

`privacy.html` and `support.html` are the two URLs App Store Connect requires
before a build can be submitted. Both are self-contained — no assets, no
scripts, no fonts to fetch — so they can be hosted anywhere.

## Publishing them

The quickest route is GitHub Pages, straight from this folder:

1. Repo → Settings → Pages
2. Source: *Deploy from a branch*, branch `main`, folder `/docs`

They then live at:

- `https://<user>.github.io/Currimus/privacy.html`
- `https://<user>.github.io/Currimus/support.html`

A custom domain is nicer if `currimus.app` exists — add a `CNAME` file here
and point the DNS at GitHub. Either way the URLs must be reachable *before*
submitting, because App Review opens them.

## Before publishing — two things to decide

**The contact address.** Both pages use `support@currimus.app`, which is a
placeholder. It has to be an address that actually receives mail, or App
Review will flag the support page. Replace it in both files:

```sh
grep -rl 'support@currimus.app' docs/ | xargs sed -i '' 's/support@currimus.app/YOUR@ADDRESS/g'
```

**The privacy policy is accurate as written, and has to stay that way.** It
says the app makes no network requests, uses no analytics and contains no
third-party SDKs. That is true today and is the strongest claim on the page.
Adding a crash reporter, an analytics package or any SDK later means editing
this file in the same commit — Apple treats a privacy policy that contradicts
the app's behaviour as a rejection, and rightly.

The same claims have to match the App Privacy answers in App Store Connect
(“Data Not Collected”) and `Resources/PrivacyInfo.xcprivacy`.
