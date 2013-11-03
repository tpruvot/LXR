###############################################
#
# $Id: hg-lxr-ext.py,v 1.1 2013/01/18 17:48:50 ajlittoz Exp $
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
###############################################

#	Mercurial plugin for LXR commands ls-onelevel and fsize

#	ls-onelevel lists only the designated directory without
#		recursively traversing sub-directories.
#		Contrary to Hg-standard ls, it reports contained
#		sub-directories (with which LXR can build links to
#		these directories).
#	fsize returns filesize
#		(otherwise, filesize can only be computed by checking
#		out file and counting characters)

#------------------------------------------------
from mercurial import cmdutil
import mercurial.hgweb.webcommands

cmdtable = {}
command = cmdutil.command(cmdtable)

@command('ls-onelevel',
        [('r', 'rev', '.',
          'revision to list')],
        'hg ls-onelevel [-r REV] [path]')
def lxrls(ui, repo, path='', rev='.'):

	files = {}
	dirs = {}
	ctx = repo[rev]
	mf = ctx.manifest()
	if path and not path.endswith('/'):
		path += '/'
	l = len(path)

	for full, n in mf.iteritems():
		f = mercurial.hgweb.webcommands.decodepath(full)

		if f[:l] != path:
			continue
		remain = f[l:]
		elements = remain.split('/')
		if len(elements) == 1:
			files[remain] = full
		else:
			h = dirs # need to retain ref to dirs (root)
			elem = elements[0]
			if elem not in h:
				h[elem] = {}

	for d in sorted(dirs):
		ui.write('%s/\n' % (d))

	for f in sorted(files):
		full = files[f]
		ui.write('%s\n' % (f))

#------------------------------------------------

@command('fsize',
        [('r', 'rev', '.',
          'return file size')],
        'hg fsize [-r REV] [path]')
def lxrfsize(ui, repo, path='', rev='.'):

	ctx = repo[rev]
	if path and path.endswith('/'):
		ui.write('0\n')
		return

	fctx = ctx.filectx(path)
	ui.write('%d\n' % (fctx.size()))
