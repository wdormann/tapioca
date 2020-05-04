# BEGIN LICENSE #
#
# CERT Tapioca
#
# Copyright 2018 Carnegie Mellon University. All Rights Reserved.
#
# NO WARRANTY. THIS CARNEGIE MELLON UNIVERSITY AND SOFTWARE
# ENGINEERING INSTITUTE MATERIAL IS FURNISHED ON AN "AS-IS" BASIS.
# CARNEGIE MELLON UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER
# EXPRESSED OR IMPLIED, AS TO ANY MATTER INCLUDING, BUT NOT LIMITED
# TO, WARRANTY OF FITNESS FOR PURPOSE OR MERCHANTABILITY, EXCLUSIVITY,
# OR RESULTS OBTAINED FROM USE OF THE MATERIAL. CARNEGIE MELLON
# UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND WITH RESPECT TO
# FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.
#
# Released under a BSD (SEI)-style license, please see license.txt or
# contact permission@sei.cmu.edu for full terms.
#
# [DISTRIBUTION STATEMENT A] This material has been approved for
# public release and unlimited distribution.  Please see Copyright
# notice for non-US Government use and distribution.
# CERT(R) is registered in the U.S. Patent and Trademark Office by
# Carnegie Mellon University.
#
# DM18-0637
#
# END LICENSE #


from PyQt5.QtWidgets import QApplication, QWidget, QPushButton, QMessageBox, QInputDialog
from PyQt5.QtGui import QIcon
from PyQt5.QtCore import pyqtSlot


app = QApplication([])
win = QWidget()
msgBox = QMessageBox()

def YesNo(question='', caption='Tapioca'):
    msgBox.setIcon(QMessageBox.Question)
    msgBox.setText(message)
    msgBox.setWindowTitle(caption)
    msgBox.setStandardButtons(QMessageBox.Yes, QMessageBox.No)
    ret = msgBox.exec()
    if ret == QMessageBox.Yes:
        return True
    else:
        return False

#    dlg = wx.MessageDialog(
#        parent, question, caption, wx.YES_NO | wx.ICON_QUESTION)
#    result = dlg.ShowModal() == wx.ID_YES
#    dlg.Destroy()
#    return result


def Info(message='', caption='Tapioca'):
    msgBox.setIcon(QMessageBox.Information)
    msgBox.setText(message)
    msgBox.setWindowTitle(caption)
    msgBox.setStandardButtons(QMessageBox.Ok)
    msgBox.exec()

#    dlg = wx.MessageDialog(
#        parent, message, caption, wx.OK | wx.ICON_INFORMATION)
#    dlg.ShowModal()
#    dlg.Destroy()


def Warn(message='', caption='Warning!'):
    msgBox.setIcon(QMessageBox.Warning)
    msgBox.setText(message)
    msgBox.setWindowTitle(caption)
    msgBox.setStandardButtons(QMessageBox.Ok)
    msgBox.exec()

#    dlg = wx.MessageDialog(parent, message, caption, wx.OK | wx.ICON_WARNING)
#    dlg.ShowModal()
#    dlg.Destroy()


def Ask(message='', caption='Tapioca', default_value=''):
    text, ok = QInputDialog.getText(win, caption, message)
    return text
    #testname, okPressed = QInputDialog.getItem(self, caption, message)
    #msgBox.setIcon(QMessageBox.Information)
    #askBox.setTextValue(message)
    #askBox.setWindowTitle(caption)
    #askBox.setStandardButtons(QMessageBox.Ok | QMessageBox.Cancel)
    #returnValue = 
    
    
#    dlg = wx.TextEntryDialog(
#        parent, message, caption, defaultValue=default_value)
#    dlg.ShowModal()
#    result = dlg.GetValue()
#    dlg.Destroy()
#    return result
