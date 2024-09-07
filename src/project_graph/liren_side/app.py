from abc import ABCMeta, abstractmethod
import sys
from pathlib import Path
from typing import Callable

from appdirs import user_data_dir
from PyQt5.QtGui import QKeyEvent, QPaintEvent
from PyQt5.QtWidgets import QApplication, QMainWindow

from project_graph.liren_side.components import Component


class _NativeWindow(QMainWindow):
    def __init__(
        self, root: Component, init: Callable[[QMainWindow], None] = lambda _: None
    ):
        super().__init__()
        self.root = root
        init(self)

    def paintEvent(self, a0: QPaintEvent | None):
        assert a0 is not None
        self.root.paintEvent(self, a0)

    def keyPressEvent(self, a0: QKeyEvent | None):
        assert a0 is not None
        self.root.keyPressEvent(self, a0)

    def keyReleaseEvent(self, a0: QKeyEvent | None):
        assert a0 is not None
        self.root.keyReleaseEvent(self, a0)


class AppConfig(metaclass=ABCMeta):
    @abstractmethod
    def main_window(self, application: QApplication) -> QMainWindow:
        pass


class App:
    __creat_key = object()

    def __init__(self, create_key: object, config: AppConfig):
        assert create_key == App.__creat_key, "the constructor of App is private"
        self.__app = QApplication(sys.argv)
        self.__window = config.main_window(self.__app)

    def run(self):
        self.__window.show()
        sys.exit(self.__app.exec_())

    @staticmethod
    def get_data_dir(app_name: str):
        data_dir = user_data_dir(app_name, "LiRen")
        if not Path(data_dir).exists():
            Path(data_dir).mkdir(parents=True, exist_ok=True)
        return data_dir

    @staticmethod
    def create(config: AppConfig) -> "App":
        return App(App.__creat_key, config)
