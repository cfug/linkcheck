import 'dart:io' show Stdout;
import 'dart:math' show min;

import 'package:console/console.dart';

import 'crawl.dart' show CrawlResult;
import 'destination.dart';
import 'link.dart';

/// Writes the reports from the perspective of a website writer - which pages
/// reference broken links.
void reportForWriters(CrawlResult result, bool ansiTerm,
    bool shouldCheckAnchors, bool showRedirects, Stdout stdout) {
  void print(Object message) => stdout.writeln(message);

  print("");

  Set<Link> links = result.links;

  /// Links that were found broken or had a warning or were redirected.
  List<Link> problematic = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped &&
          (link.destination.isInvalid ||
              link.destination.wasTried &&
                  (link.destination.isBroken ||
                      link.hasWarning(shouldCheckAnchors) ||
                      (showRedirects && link.destination.isRedirected))))
      .toList(growable: false);

  List<Destination> deniedByRobots = result.destinations
      .where((destination) => destination.wasDeniedByRobotsTxt)
      .toList(growable: false);
  deniedByRobots.sort((a, b) => a.url.compareTo(b.url));

  List<Uri> sourceUris = problematic
      .map((link) => link.origin.uri)
      .toSet()
      .toList(growable: false);
  sourceUris.sort((a, b) => a.toString().compareTo(b.toString()));

  TextPen? ansiPen;
  if (ansiTerm) {
    ansiPen = TextPen();
  }

  List<Destination> brokenSeeds = result.destinations
      .where((destination) => destination.isSeed && destination.isBroken)
      .toList(growable: false);
  brokenSeeds.sort((a, b) => a.toString().compareTo(b.toString()));

  if (brokenSeeds.isNotEmpty) {
    print("Provided URLs failing:");
    for (var destination in brokenSeeds) {
      if (ansiPen != null) {
        ansiPen
            .reset()
            .yellow()
            .text(destination.url)
            .lightGray()
            .text(" (")
            .red()
            .text(destination.statusDescription)
            .lightGray()
            .text(')')
            .normal()
            .print();
      } else {
        print("${destination.url} (${destination.statusDescription})");
      }
    }

    print("");
  }

  if (deniedByRobots.isNotEmpty) {
    print("Access to these URLs denied by robots.txt, "
        "so we couldn't check them:");
    for (var destination in deniedByRobots) {
      if (ansiPen != null) {
        ansiPen
            .reset()
            .normal()
            .text("- ")
            .yellow()
            .text(destination.url)
            .normal()
            .print();
      } else {
        print("- ${destination.url}");
      }
    }

    print("");
  }

  // TODO: summarize when there are huge amounts of sourceURIs for a broken link
  // TODO: report invalid links

  for (var uri in sourceUris) {
    if (ansiPen != null) {
      printWithAnsi(uri, problematic, ansiPen);
    } else {
      printWithoutAnsi(uri, problematic, stdout);
    }
  }

  List<Link> broken =
      problematic.where((link) => link.hasError).toList(growable: false);
  if (broken.isNotEmpty && broken.length < problematic.length / 2) {
    // Reiterate really broken links if the listing above is mostly warnings
    // with only a minority of errors. The user cares about errors first.
    print("");
    print("Summary of most serious issues:");
    print("");

    List<Uri> brokenUris =
        broken.map((link) => link.origin.uri).toSet().toList(growable: false);
    brokenUris.sort((a, b) => a.toString().compareTo(b.toString()));

    for (var uri in brokenUris) {
      if (ansiPen != null) {
        printWithAnsi(uri, broken, ansiPen);
      } else {
        printWithoutAnsi(uri, broken, stdout);
      }
    }
  }
}

void printWithAnsi(Uri uri, List<Link> broken, TextPen pen) {
  pen.reset();
  pen.setColor(Color.YELLOW).text(uri.toString()).normal().print();

  var links = broken.where((link) => link.origin.uri == uri);
  for (var link in links) {
    String tag = _buildTagSummary(link);
    pen.reset();
    pen
        .normal()
        .text("- ")
        .lightGray()
        .text("(")
        .normal()
        .text("${link.origin.span.start.line + 1}")
        .lightGray()
        .text(":")
        .normal()
        .text("${link.origin.span.start.column}")
        .lightGray()
        .text(") ")
        .magenta()
        .text(tag)
        .lightGray()
        .text("=> ")
        .normal()
        .text(link.destination.url)
        .lightGray()
        .text(link.fragment == null ? '' : '#${link.fragment}')
        .text(" (")
        .setColor(link.hasError ? Color.RED : Color.YELLOW)
        .text(link.destination.statusDescription)
        .yellow()
        .text(!link.hasError && link.breaksAnchor ? ' but missing anchor' : '')
        .lightGray()
        .text(')')
        .normal()
        .print();

    if (link.destination.isRedirected) {
      print("  - redirect path:");
      String current = link.destination.url;
      for (var redirect in link.destination.redirects) {
        print("    - $current (${redirect.statusCode})");
        current = redirect.url;
      }
      print("    - $current (${link.destination.statusCode})");
    }
  }
  print("");
}

void printWithoutAnsi(Uri uri, List<Link> broken, Stdout stdout) {
  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  print(uri);

  var links = broken.where((link) => link.origin.uri == uri);
  for (var link in links) {
    String tag = _buildTagSummary(link);
    var linkFragment = link.fragment;
    print("- (${link.origin.span.start.line + 1}"
        ":${link.origin.span.start.column}) "
        "$tag"
        "=> ${link.destination.url}"
        "${linkFragment == null ? '' : '#$linkFragment'} "
        "(${link.destination.statusDescription}"
        "${!link.destination.isBroken && link.breaksAnchor ? ' but missing anchor' : ''}"
        ")");
    if (link.destination.isRedirected) {
      print("  - redirect path:");
      String current = link.destination.url;
      for (var redirect in link.destination.redirects) {
        print("    - $current (${redirect.statusCode})");
        current = redirect.url;
      }
      print("    - $current (${link.destination.statusCode})");
    }
  }
  print("");
}

String _buildTagSummary(Link link) {
  String tag = "";
  if (link.origin.tagName == 'a') {
    const maxLength = 10;
    var text = link.origin.text.replaceAll("\n", " ").trim();
    int length = text.length;
    if (length > 0) {
      if (length <= maxLength) {
        tag = "'$text' ";
      } else {
        tag = "'${text.substring(0, min(length, maxLength - 2))}..' ";
      }
    }
  } else if (link.origin.uri.path.endsWith(".css") &&
      link.origin.tagName == "url") {
    tag = "url(...) ";
  } else {
    tag = "<${link.origin.tagName}> ";
  }
  return tag;
}
