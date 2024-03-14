// Asymptote library for repositionable, tranformable "nodes" consisting of
// internal text or images and a bounding box.
// Nodes can be moved relative to one another, and points on a node's bounding box
// are easily accessible.

// UTIL FUNCTIONS
// map overloaded for pairs of reals
pair[] map(pair f(real), real[] x) {
  pair[] r = new pair[x.length];
  return sequence(new pair(int i) {return f(x[i]);}, x.length);
}

// dot but bigger
void debugPoint(pair p, pen q = red) {
  draw(circle(p, 3), q);
}

// Move along path p from point i by one segment length
real tick(real i, path p, int segments) {
    return i + (length(p)/segments);
}

// Divide path P into (segment) segments, and return the segment boundaries as points
pair[] points_along(path p, int segments) {
    pair[] out = new pair[];
    real stepsize = arclength(p)/segments;
    for(real i=0; i <= arclength(p) - realEpsilon; i = i + stepsize) {
        out.push(arcpoint(p, i));
    };
    return out;
}

// Put the label (l) at position (pos), return the bounding box
path labelAndBounds(Label l, pair pos, pen p = invisible, int margins = 3) {
  frame f;
  label(f, l, Center);
  add(f, pos);
  return shift(pos)*box(f, margins, margins, p);
}

// Return the tightest possible box that encloses all paths in the input
path boxAround(path[] paths) {
  real top;
  real bot;
  real left;
  real right;

  for (path p : paths) {
    // min x, min y, max x, max y;
    real[] times = concat(mintimes(p), maxtimes(p));
    pair[] points;
    for(real t : times) {points.push(point(p, t));}
    
    if(points[0].x < left) { left = points[0].x; }
    if(points[1].y < bot) { bot = points[1].y; }
    if(points[2].x > right) { right = points[2].x; }
    if(points[3].y > top) { top = points[3].y; }
  }

  return (left, bot) -- (right, bot) -- (right, top) -- (left, top) -- cycle;
}
// Do that with a VarArgs
path boxAround(...path[] paths) { return boxAround(paths); }

// Place all labels at uniform distances along p, return all bounding boxes
// Optionally draw the path "under" the labels
path[] labelAlongPath (path p, Label[] labels, bool drawPath = false) {
  int n = labels.length;
  pair[] points = points_along(p, n);

  // place labels and get bounding boxes
  path f(int i) {return labelAndBounds(labels[i], points[i]);}
  path[] bounds = sequence(f, n);

  // intersections of boxes with p
  real[] touchPoints;
  for(int i = 0; i < n; ++i) {
    real[][] allIntersections = intersections(p, bounds[i]);
    touchPoints.push(allIntersections[1][0]);
    touchPoints.push(allIntersections[0][0]);
  }

  touchPoints = sort(touchPoints);

  // draw path between em
  if (drawPath) {
  for(int t = 0; t < (2*n); t = t + 2) {
    draw(subpath(p, touchPoints[t], touchPoints[t+1]));
  }
  };

  return bounds;
}

// Cardinals and ordinals as pairs for use with anchor
pair north = (0, 1);
pair south = (0, -1);
pair east = (1, 0);
pair west = (-1, 0);
pair northeast = unit(north + east);
pair northwest = unit(north + west);
pair southeast = unit(south + east);
pair southwest = unit(south + west);

// get the relative path around l (ie. no placement offset)
path bounds(Label l, real xmargin = 3, real ymargin = xmargin) {
  frame f;
  label(f, l, Center);
  return box(f, xmargin, ymargin, invisible);
}

// Get a path parallel(-ish) to p, scaled by (scale).
// This is implemented stupidly and generates a lot of control points, so
// don't nest calls to it. Turns out parallel splines are complicated.
// The (incr) parameter determines how granular the calculation is, decrease
// it if the result doesn't look parallel enough.
// If the input is a straight line, using its length as (incr) works fine.
path parallel(path p, real scale = 1, real incr = 0.1) {
  guide out = shift(scale(scale)*rotate(90)*dir(p, 0))*point(p, 0);
  for (real i = incr; i <= length(p); i = i + incr) {
    pair pt = point(p, i);
    pair normal = rotate(90)*dir(p, i);
    out = out .. (shift(scale(scale)*normal)*pt);
  }
  // don't miss that last node if you used a weird incr
  out = out .. shift(scale(scale)*rotate(90)*dir(p, length(p)))*point(p, length(p));
  return out;
}

// Get the point at the centre of cyclical path p
// by assuming it's halfway between the lower left and upper right.
pair centre(path p) {
  return (midpoint(min(p) -- max(p)));
}
// Get the point at direction vec from the centre of cyclical path p
pair anchor(path p, pair vec) {
  // take the point at the centre, extend a line of the length of p 
  // in the desired direction.
  path g = centre(p) -- (centre(p) + (arclength(p)*unit(vec)));
  return intersectionpoint(p, g);
}

// Make a single path into a double path, and place an arrowhead at the end
path[] doublePath(path p, real arrowSize = 4) {
  path[] out;

  path pos = (parallel(p));
  path neg = (parallel(p, -1));

  // put the arrowhead at the end
  pair end = point(p, length(p));
  pair p1 = shift(scale(arrowSize)*rotate(135)*dir(p, length(p)))*end;
  pair p2 = shift(scale(arrowSize)*rotate(135+90)*dir(p, length(p)))*end;
  path arrow = (p1 -- end -- p2);

  out.push(subpath(pos, 0, intersect(pos, arrow)[0]));
  out.push(subpath(neg, 0, intersect(neg, arrow)[0]));
  out.push(arrow);
  return out;
}

//// TIKZ-STYLE NODES
// Type of transformations over paths, used to change node shapes
// When used as a node parameter, you can assume the input will be generated
// by boxAround.
typedef path pathtransform(path);
pathtransform pathid = new path(path p) { return p;};

// Tikz-style nodes with bounding boxes and anchors.
// Label text can't be changed, but nodes can be moved.
// Nodes won't draw by themselves, as they're mutable. You can defer positioning and
// re-position nodes as much as you like without drawing anything.
// Draw a node using the "stamp" method.
struct Node {
  restricted picture contents; // i want nodes inside nodes so here we are
  restricted path absBox;
  restricted path relBox;
  restricted pair midPoint;


  // Get the point on the absBox(or relBox if relative) at (vec) or (degrees) from the center.
  // The vector doesn't need to be a unit.
  // Pairs and reals are ambiguous in asy, so the degree version has a distinct name.
  pair anchor(pair vec, bool relative = false) {
    assert(vec != (0, 0), "Can't fetch an anchor with an angle of (0, 0).");
    path g = (0, 0) -- ((arclength(relBox)*unit(vec)));
    pair p = intersectionpoint(relBox, g);
    if(relative) {return p;}
    return shift(midPoint)*p;
  }
  pair degreeAnchor (real degrees, bool relative = false) {
    pair vec = dir(degrees);
    return anchor(vec, relative);
  }

  // Since anchors are based on an offset from the centre, they can't
  // fetch corners easily.
  // These methods fetch corners.
  pair topLeft() {
    return this.anchor((xpart(min(relBox)), ypart(max(relBox))));
  }
  pair topRight() {
    return anchor(max(relBox));
  }
  pair bottomLeft() {
    return this.anchor(min(relBox));
  }
  pair bottomRight() {
    return anchor((xpart(max(relBox)), ypart(min(relBox))));
  }

  // Move this node somewhere else
  void moveTo(pair p) {
    this.midPoint = p;
    this.absBox = shift(p)*relBox;
  }

  // Get the distance from the centre of the node to the bounding box
  // at an angle given by (vec)
  real radius(pair vec) {
    pair p = point(relBox, intersections(relBox, (0, 0), vec)[0]);
    return length(p);
  }

  // Apply a transform to everything in the node 
  // All transforms are relative to node midpoint, not the enclosing picture,
  // so rotating it 90 degrees about (0, 0) will only rotate the node and not move it.
  // This is liable to do weird things.
  void transform(transform t) {
    this.relBox = t*relBox;
    this.midPoint = shift(midPoint)*t*(0, 0);
    this.absBox = shift(midPoint)*relBox;
    this.contents = t*contents;
  }

  // Move this node to be dist away from node (n)
  // Distance is measured from bounding box to bounding box, meaning
  // a dist of (0, 0) will cause an error.
  // Use moveTouching for touching nodes.
  // Return the path between this node and (n) for convenience
  path moveNextTo(Node n, pair dist = (1cm, 0)) {
    assert(dist != (0, 0), "Distance cannot be 0, use moveTouching for adjacent boxes");
    pair exit = n.anchor(dist);
    pair entry = shift(exit)*dist;
    path edge = (exit -- entry);

    pair offset = anchor(-dist, true);
    moveTo(shift((-offset.x, -offset.y))*entry);
    return edge;
  }

  // Similar to the other nextTo, but place it relative to a group of nodes.
  path moveNextTo(pair dist = (1cm, 0) ... Node[] nodes) {
    path[] nodeBoxes;
    for(Node n : nodes) {
      nodeBoxes.push(n.absBox);
    }
    path extBox = boxAround(nodeBoxes);

    pair exit = anchor(extBox, dist);
    pair entry = shift(exit)*dist;
    path edge = (exit -- entry);

    pair offset = anchor(-dist, true);
    moveTo(shift((-offset.x, -offset.y))*entry);
    return edge;

  }

  // Place this node such that (thisAnchor) is (dist) away from (otherAnchor)
  path moveNextTo(Node n, pair thisAnchor, pair otherAnchor, pair dist = (1cm, 0)) {
    pair exit = n.anchor(otherAnchor);
    pair entry = shift(exit)*dist;
    path edge = (exit -- entry);

    pair offset = anchor(thisAnchor);
    moveTo(shift((-offset.x, -offset.y))*entry);
    return edge;
  }

  // Like nextTo, but with a distance of 0 disambiguated by dir.
  void moveTouching(Node n, pair dir = (1, 0)) {
    pair exit = n.anchor(dir);
    pair entry = anchor(-dir, true);

    moveTo(shift(-entry)*exit);
  }

  // Get a path between this node and another
  path pathTo(Node n) {
    guide line = (midPoint -- n.midPoint);
    pair out = intersectionpoint(absBox, line);
    pair in = intersectionpoint(n.absBox, line);
    return out -- in;
  }

  // Draw the node onto a given picture, or the current one if called as stamp()
  void stamp(picture pic = currentpicture) {
    add(pic, contents, midPoint);
  }

  // Make a node containing a string as a label
  // All other parameters are optional
  // The (draw) and (fill) parameters define the pen used for the bounding box, not the text.
  void operator init(string s, pen labelpen = currentpen, 
    real xmargin = 3, real ymargin = xmargin, 
    pathtransform shape = pathid, pen draw = invisible, pen fill = invisible,
    pair pos = (0,0)) 
    {
    picture pic;
    label(pic, Label(s, labelpen));
    this.relBox = shape(bounds(Label(s), xmargin, ymargin));
    filldraw(pic, relBox, fill, draw);
    this.contents = pic;
    moveTo(pos);
  }

  // Make a node of an arbitrary pic
  // The margins will be added to the input pic,
  // and the background will be drawn behind its contents.
  // If the "middle" of the input doesn't have relative co-ordinates (0, 0),
  // you can input the actual middle as a parameter. This will shift the 
  // contents of pic until the given midpoint really is (0, 0).
  void operator init(picture pic,
    real xmargin=3, real ymargin = xmargin, pair midpoint = (0, 0),
    pathtransform shape = pathid, pen draw = invisible, pen fill = invisible,
    pair pos = (0, 0)) {
    // fill should add to the background, so fill "beneath" the contents then draw
    picture newpic;
    pair pmax = pic.max() + (xmargin, ymargin);
    pair pmin = pic.min() + (-xmargin, -ymargin);
    path box = pmin -- (xpart(pmin), ypart(pmax)) -- pmax -- (xpart(pmax), ypart(pmin)) -- cycle;
    box = shift(-midpoint)*box;
    this.relBox = shape(box);
    // fill the expected shape with bg colour, add contents, draw outline
    fill(newpic, relBox, fill);
    newpic.add(shift(-midpoint)*pic);
    draw(newpic, relBox, draw);
    this.contents = newpic;
    moveTo(pos);
  }
}

// By default, treat a Node as its absBox for functions expecting a path
path operator cast(Node n) { return n.absBox; }

// Draw the node by a deferred call to stamp, if you wanted to use that notation
void draw(picture pic = currentpicture, Node n) {
  n.stamp(pic);
}

// Likewise for onPic
void onPic(picture p ... Node[] ns) {
  for(Node n : ns) {
    n.stamp(p);
  }
}

// Box with rounded edges for use as a "shape" parameter
pathtransform roundedBox = new path(path p) {
  // round edges by 3pt, since that's roughly what the tikz did
  pair[] corners;
  for (int i = 0; i < 4; i = i + 1) { 
    corners.push(point(p, i) - (6pt * dir(p, i-0.1)));
    corners.push(point(p, i) + (6pt * dir(p, i+0.1)));
  }
  guide ret = corners[0];
  for (int i = 0; i < 7; i = i + 2) { 
    ret = ret -- corners[i].. controls point(p, i/2) .. corners[i+1];
  }
  ret = ret -- cycle;
  return ret;
};