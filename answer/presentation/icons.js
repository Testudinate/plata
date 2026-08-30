const React = require('react');
const ReactDOMServer = require('react-dom/server');
const sharp = require('sharp');
const Fi = require('react-icons/fi');

// Renders a react-icons component to a base64 PNG data URI string usable in addImage({data:...})
async function iconPng(name, colorHex, sizePx = 256) {
  const Comp = Fi[name];
  if (!Comp) throw new Error('Unknown icon: ' + name);
  const svgFull = ReactDOMServer.renderToStaticMarkup(
    React.createElement(Comp, { color: '#' + colorHex, size: sizePx })
  );
  const buf = await sharp(Buffer.from(svgFull)).resize(sizePx, sizePx).png().toBuffer();
  return 'image/png;base64,' + buf.toString('base64');
}

module.exports = { iconPng };
