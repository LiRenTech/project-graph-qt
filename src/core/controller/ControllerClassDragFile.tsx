import { Vector } from "../dataStruct/Vector";

/**
 * 专门用来处理文件拖拽的类
 */
export class ControllerClassDragFile {
  constructor() {}

  public lastMoveLocation: Vector = Vector.getZero();

  public dragEnter = (_: DragEvent) => {};
  public dragOver = (_: DragEvent) => {};
  public dragLeave = (_: DragEvent) => {};
  public drop = (_: DragEvent) => {};

  public init() {
    window.addEventListener("dragenter", this.dragEnter, false);
    window.addEventListener("dragover", this.dragOver, false);
    window.addEventListener("dragleave", this.dragLeave, false);
    window.addEventListener("drop", this.drop, false);
  }
  public destroy() {
    window.removeEventListener("dragenter", this.dragEnter);
    window.removeEventListener("dragover", this.dragOver);
    window.removeEventListener("dragleave", this.dragLeave);
    window.removeEventListener("drop", this.drop);
    console.log(this.lastMoveLocation);
    this.lastMoveLocation = Vector.getZero();
  }
}
